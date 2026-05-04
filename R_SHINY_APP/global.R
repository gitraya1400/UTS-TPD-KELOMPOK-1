# ==============================================================================
# LIVESTOCK INTELLIGENCE - R SHINY DASHBOARD
# global.R: Library Setup, Database Connection, Spatial Data Initialization
# ==============================================================================

# ============================================================================
# 1. LOAD REQUIRED LIBRARIES
# ============================================================================

# Shiny & UI Framework
library(shiny)
library(shinydashboard)
library(shinyWidgets)
library(shinyalert)

# Database & Data Manipulation
library(DBI)
library(RPostgres)
library(dplyr)
library(dbplyr)
library(tidyr)

# Spatial Data & Mapping
library(sf)              # For reading shapefile and spatial operations
library(leaflet)         # For interactive maps
library(leaflet.extras)

# Data Visualization
library(plotly)
library(ggplot2)
library(scales)
library(treemapify)
library(grid)
library(gridExtra)

# Data Processing & Statistics
library(tidyverse)
library(lubridate)
library(zoo)             # For time series operations
library(corrplot)

# Utilities
library(lubridate)
library(scales)
library(formattable)

# ==============================================================================
# 2. DATABASE CONNECTION SETUP
# ==============================================================================

# IMPORTANT: Replace with your actual database credentials
# In production, use environment variables or Shiny secrets instead of hardcoding

db_config <- list(
  host = Sys.getenv("DB_HOST", "localhost"),
  port = as.numeric(Sys.getenv("DB_PORT", 5432)),
  dbname = Sys.getenv("DB_NAME", "datawarehouse_db"),
  user = Sys.getenv("DB_USER", "postgres"),
  password = Sys.getenv("DB_PASSWORD", "")
)

# Create global database connection
con <- tryCatch({
  dbConnect(
    RPostgres::Postgres(),
    host = db_config$host,
    port = db_config$port,
    dbname = db_config$dbname,
    user = db_config$user,
    password = db_config$password,
    bigint = "integer"
  )
}, error = function(e) {
  warning(paste("Database connection failed:", e$message))
  NULL
})

# Verify connection
if (!is.null(con)) {
  cat("✓ Database connection successful\n")
} else {
  stop("Failed to connect to database. Please check credentials in global.R")
}

# ==============================================================================
# 3. LOAD & PROCESS SPATIAL DATA (SHAPEFILE)
# ==============================================================================

# Read shapefile: ADMINISTRAS_PROVINSI.shp
# Join key: nama_provinsi (standardized from dim_prov)
shapefile_path <- "data/ADMINISTRAS_PROVINSI.shp"

spatial_data <- tryCatch({
  st_read(shapefile_path, quiet = TRUE)
}, error = function(e) {
  warning(paste("Shapefile not found:", shapefile_path))
  NULL
})

if (!is.null(spatial_data)) {
  cat("✓ Spatial data loaded:", nrow(spatial_data), "regions\n")
  
  # Standardize province names in shapefile
  # Assuming the shapefile has a column named 'Provinsi' or similar
  # Adjust column name according to your actual shapefile structure
  if ("Provinsi" %in% names(spatial_data)) {
    spatial_data$nama_provinsi <- toupper(trimws(spatial_data$Provinsi))
  } else if ("PROVINSI" %in% names(spatial_data)) {
    spatial_data$nama_provinsi <- toupper(trimws(spatial_data$PROVINSI))
  }
} else {
  cat("⚠ Spatial data not available. Choropleth map will be disabled.\n")
}

# ==============================================================================
# 4. PRE-LOAD REFERENCE DATA FOR UI
# ==============================================================================

# Load province list from database for UI dropdown
if (!is.null(con)) {
  prov_list <- dbGetQuery(con, "
    SELECT DISTINCT nama_provinsi 
    FROM dim_prov 
    ORDER BY nama_provinsi ASC
  ") %>%
    pull(nama_provinsi) %>%
    c("Nasional", .)
  
  # Load commodity list
  komoditas_list <- dbGetQuery(con, "
    SELECT nama_komoditas 
    FROM dim_komoditas 
    ORDER BY komoditas_key ASC
  ") %>%
    pull(nama_komoditas)
  
  # Load time range for slider
  time_range <- dbGetQuery(con, "
    SELECT MIN(tahun) as min_year, MAX(tahun) as max_year 
    FROM dim_waktu
  ")
  
  min_year <- time_range$min_year[1]
  max_year <- time_range$max_year[1]
  
  cat("✓ Reference data loaded for UI\n")
} else {
  prov_list <- c("Nasional")
  komoditas_list <- c("Sapi", "Ayam")
  min_year <- 2020
  max_year <- 2025
}

# ==============================================================================
# 5. UTILITY FUNCTIONS FOR OLAP OPERATIONS
# ==============================================================================

# Function: Query aggregated data with OLAP operations
# Uses dbplyr for in-database processing (Query Pushdown)
query_supply_resilience <- function(
    prov = "Nasional",
    komoditas = "Sapi",
    year_range = c(min_year, max_year),
    months = 1:12) {
  
  if (is.null(con)) return(NULL)
  
  # Reference fact table via dbplyr
  fact_tbl <- tbl(con, "fact_supply_resilience")
  prov_tbl <- tbl(con, "dim_prov")
  waktu_tbl <- tbl(con, "dim_waktu")
  komoditas_tbl <- tbl(con, "dim_komoditas")
  
  # Build query with filters (SLICING & DICING)
  query <- fact_tbl %>%
    left_join(prov_tbl, by = "prov_key") %>%
    left_join(waktu_tbl, by = "waktu_key") %>%
    left_join(komoditas_tbl, by = "komoditas_key")
  
  # Filter by province (SLICING)
  if (prov != "Nasional") {
    query <- query %>%
      filter(nama_provinsi == prov)
  }
  
  # Filter by commodity (SLICING)
  query <- query %>%
    filter(nama_komoditas == komoditas)
  
  # Filter by year range (DICING)
  query <- query %>%
    filter(tahun >= year_range[1] & tahun <= year_range[2])
  
  # Filter by months (DICING)
  query <- query %>%
    filter(bulan %in% months)
  
  # CRITICAL: Use collect() only AFTER all filtering/aggregation at database level
  # This ensures Query Pushdown - aggregation happens in PostgreSQL, not R
  result <- query %>%
    collect()
  
  return(result)
}

# Function: Calculate top N provinces by supply risk
get_top_provinces <- function(n = 5, komoditas = "Sapi") {
  if (is.null(con)) return(NULL)
  
  top_prov <- dbGetQuery(con, paste("
    SELECT 
      p.nama_provinsi,
      ROUND(AVG(f.supply_risk_index)::numeric, 4) AS avg_risk_index,
      COUNT(*) AS data_points
    FROM fact_supply_resilience f
    JOIN dim_prov p ON f.prov_key = p.prov_key
    JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
    WHERE k.nama_komoditas = '", komoditas, "'
    GROUP BY p.nama_provinsi
    ORDER BY avg_risk_index DESC
    LIMIT ", n, "
  ", sep = ""))
  
  return(top_prov)
}

# Function: Get national aggregated metrics
get_national_metrics <- function(komoditas = "Sapi") {
  if (is.null(con)) return(NULL)
  
  metrics <- dbGetQuery(con, paste("
    SELECT 
      ROUND(AVG(supply_risk_index)::numeric, 4) AS national_risk_index,
      ROUND(AVG(avg_harga)::numeric, 2) AS avg_price,
      ROUND(SUM(sum_jumlah_sakit)::numeric, 0) AS total_sick,
      ROUND(SUM(sum_vol_mutasi)::numeric, 0) AS total_supply_volume
    FROM fact_supply_resilience f
    JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
    WHERE k.nama_komoditas = '", komoditas, "'
  ", sep = ""))
  
  return(metrics)
}

# Function: Spatial join shapefile with supply risk data
# Returns sf object with risk index mapped to geometry
join_spatial_risk <- function(komoditas = "Sapi") {
  if (is.null(spatial_data) || is.null(con)) return(NULL)
  
  # Get latest risk data per province
  risk_data <- dbGetQuery(con, paste("
    SELECT 
      p.nama_provinsi,
      ROUND(AVG(f.supply_risk_index)::numeric, 4) AS risk_index,
      ROUND(SUM(f.sum_jumlah_sakit)::numeric, 0) AS total_sick,
      ROUND(AVG(f.populasi_ternak)::numeric, 0) AS avg_livestock
    FROM fact_supply_resilience f
    JOIN dim_prov p ON f.prov_key = p.prov_key
    JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
    WHERE k.nama_komoditas = '", komoditas, "'
    GROUP BY p.nama_provinsi
  ", sep = ""))
  
  if (nrow(risk_data) == 0) return(NULL)
  
  # Standardize province names for joining
  risk_data$nama_provinsi <- toupper(trimws(risk_data$nama_provinsi))
  spatial_data_copy <- spatial_data
  spatial_data_copy$nama_provinsi <- toupper(trimws(spatial_data_copy$nama_provinsi))
  
  # Perform spatial left join
  spatial_joined <- spatial_data_copy %>%
    left_join(
      st_drop_geometry(risk_data),
      by = "nama_provinsi",
      match.fun = function(x, y) x == y
    )
  
  return(spatial_joined)
}

# Function: Calculate supply-demand gap
calculate_supply_demand_gap <- function(prov = "DKI Jakarta", komoditas = "Sapi") {
  if (is.null(con)) return(NULL)
  
  gap_data <- dbGetQuery(con, paste("
    SELECT 
      p.nama_provinsi,
      ROUND(AVG(f.sum_vol_mutasi)::numeric, 2) AS avg_volume_supply_ekor,
      ROUND(AVG(f.avg_permintaan_bulanan)::numeric, 2) AS avg_demand_ekor,
      ROUND(AVG(f.sum_realisasi_karkas)::numeric, 2) AS avg_karkas_kg,
      ROUND(AVG(f.avg_konsumsi_bulanan)::numeric, 2) AS avg_consumption_kg,
      ROUND((AVG(f.sum_vol_mutasi) - AVG(f.avg_permintaan_bulanan))::numeric, 2) AS gap_ekor,
      ROUND((AVG(f.sum_realisasi_karkas) - AVG(f.avg_konsumsi_bulanan))::numeric, 2) AS gap_kg
    FROM fact_supply_resilience f
    JOIN dim_prov p ON f.prov_key = p.prov_key
    JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
    WHERE k.nama_komoditas = '", komoditas, "'
      AND p.nama_provinsi = '", prov, "'
    GROUP BY p.nama_provinsi
  ", sep = ""))
  
  return(gap_data)
}

# Function: Calculate supply dependency (concentration analysis)
calculate_supply_dependency <- function(target_region = "DKI Jakarta", komoditas = "Sapi") {
  if (is.null(con)) return(NULL)
  
  dependency <- dbGetQuery(con, paste("
    SELECT 
      p.nama_provinsi,
      ROUND(SUM(f.sum_vol_mutasi)::numeric, 2) AS total_volume,
      ROUND((SUM(f.sum_vol_mutasi) / 
        (SELECT SUM(f2.sum_vol_mutasi) 
         FROM fact_supply_resilience f2
         JOIN dim_komoditas k2 ON f2.komoditas_key = k2.komoditas_key
         WHERE k2.nama_komoditas = '", komoditas, "') * 100)::numeric, 2) AS percentage_national
    FROM fact_supply_resilience f
    JOIN dim_prov p ON f.prov_key = p.prov_key
    JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
    WHERE k.nama_komoditas = '", komoditas, "'
    GROUP BY p.nama_provinsi
    ORDER BY total_volume DESC
  ", sep = ""))
  
  return(dependency)
}

# Function: Calculate correlation between price and disease
calculate_price_disease_correlation <- function(prov = NULL, komoditas = "Sapi") {
  if (is.null(con)) return(NULL)
  
  corr_data <- dbGetQuery(con, paste("
    SELECT 
      f.tahun,
      f.bulan,
      ROUND(AVG(f.avg_harga)::numeric, 2) AS avg_price,
      ROUND(SUM(f.sum_jumlah_sakit)::numeric, 0) AS total_sick,
      ROUND(SUM(f.sum_jumlah_mati)::numeric, 0) AS total_dead,
      p.nama_provinsi
    FROM fact_supply_resilience f
    JOIN dim_prov p ON f.prov_key = p.prov_key
    JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
    WHERE k.nama_komoditas = '", komoditas, "'",
    ifelse(is.null(prov), "", paste(" AND p.nama_provinsi = '", prov, "'")),
    "
    GROUP BY f.tahun, f.bulan, p.nama_provinsi
    ORDER BY f.tahun ASC, f.bulan ASC
  ", sep = ""))
  
  return(corr_data)
}

# ==============================================================================
# 6. COLOR SCHEME & THEME CONFIGURATION
# ==============================================================================

# Color palette for supply risk index (0 = Green, 1 = Red)
color_risk_palette <- function(value) {
  # value should be between 0 and 1
  if (value < 0.33) {
    return("#2ecc71")  # Green (Safe)
  } else if (value < 0.67) {
    return("#f39c12")  # Orange (Warning)
  } else {
    return("#e74c3c")  # Red (Danger)
  }
}

# Leaflet color palette for choropleth
leaflet_risk_palette <- colorNumeric(
  palette = c("#2ecc71", "#f39c12", "#e74c3c"),
  domain = c(0, 1),
  na.color = "#d3d3d3"
)

# ==============================================================================
# 7. SHUTDOWN HOOK
# ==============================================================================

# Ensure database connection is closed when Shiny app shuts down
onStop(function() {
  if (!is.null(con)) {
    dbDisconnect(con)
    cat("Database connection closed\n")
  }
})

cat("✓ global.R initialization complete\n")
