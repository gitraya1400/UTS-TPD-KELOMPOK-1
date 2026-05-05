
# =============================================================================
# LIVESTOCK INTELLIGENCE - CONFIGURATION FILE
# =============================================================================

# =================== DATABASE CONFIGURATION ===================
DB_CONFIG <- list(
  host = Sys.getenv("DB_HOST", "localhost"),
  port = as.integer(Sys.getenv("DB_PORT", "5432")),
  dbname = Sys.getenv("DB_NAME", "datawarehouse_db"),
  user = Sys.getenv("DB_USER", "postgres"),
  password = Sys.getenv("DB_PASSWORD", "")
)

# =================== THRESHOLD CONFIGURATION ===================
RISK_THRESHOLDS <- list(
  critical = 0.7,
  warning = 0.5,
  caution = 0.3,
  safe = 0.0
)

DISEASE_DENSITY_QUANTILE <- 0.75  # Top 25% considered high density
CORRELATION_THRESHOLD <- 0.7       # r > 0.7 = strong correlation

# =================== COLOR PALETTE ===================
COLOR_PALETTE <- list(
  risk_critical = "#d62728",      # Red
  risk_warning = "#ff7f0e",       # Orange
  risk_caution = "#ffc107",       # Yellow
  risk_safe = "#2ca02c",          # Green
  primary = "#0066cc",             # Blue
  secondary = "#6c757d",           # Gray
  success = "#28a745",             # Green
  danger = "#dc3545",              # Dark Red
  info = "#17a2b8",                # Cyan
  light = "#f8f9fa",               # Light Gray
  dark = "#343a40"                 # Dark Gray
)

# =================== SPATIAL CONFIGURATION ===================
SPATIAL_CONFIG <- list(
  shapefile_path = "data/ADMINISTRAS_PROVINSI.shp",
  center_lat = -0.789,             # Indonesia center
  center_lon = 113.921,
  zoom_level = 5,
  color_column = "supply_risk_index"
)

# =================== ALERT STATUS ===================
get_alert_status <- function(risk_index) {
  if (risk_index >= RISK_THRESHOLDS$critical) {
    return(list(status = "CRITICAL", icon = "🔴", color = COLOR_PALETTE$risk_critical))
  } else if (risk_index >= RISK_THRESHOLDS$warning) {
    return(list(status = "WARNING", icon = "🟠", color = COLOR_PALETTE$risk_warning))
  } else if (risk_index >= RISK_THRESHOLDS$caution) {
    return(list(status = "CAUTION", icon = "🟡", color = COLOR_PALETTE$risk_caution))
  } else {
    return(list(status = "SAFE", icon = "🟢", color = COLOR_PALETTE$risk_safe))
  }
}

# =================== DATABASE CONNECTION ===================
create_db_connection <- function() {
  tryCatch(
    {
      con <- dbConnect(
        RPostgres::Postgres(),
        host = DB_CONFIG$host,
        port = DB_CONFIG$port,
        dbname = DB_CONFIG$dbname,
        user = DB_CONFIG$user,
        password = DB_CONFIG$password,
        timeout = 30
      )
      return(con)
    },
    error = function(e) {
      stop(sprintf("Database connection failed: %s", e$message))
    }
  )
}

# =================== UTILITY FUNCTIONS ===================

# Format currency for Rupiah
format_rupiah <- function(x) {
  format(x, big.mark = ".", decimal.mark = ",", scientific = FALSE, trim = TRUE)
}

# Format percentage
format_percent <- function(x, digits = 2) {
  paste0(round(x * 100, digits), "%")
}

# Standardize province names to uppercase (BPS standard)
standardize_province_name <- function(prov_name) {
  return(toupper(trimws(prov_name)))
}

# Create month label (e.g., "2024-01" -> "Jan 2024")
create_month_label <- function(tahun, bulan) {
  month_names <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", 
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
  return(paste(month_names[bulan], tahun))
}

# Risk zone classification
classify_risk_zone <- function(risk_idx, disease_density, disease_density_threshold) {
  if (risk_idx >= RISK_THRESHOLDS$warning && disease_density > disease_density_threshold) {
    return("RED ZONE - Prioritas Utama")
  } else if (risk_idx >= RISK_THRESHOLDS$warning || disease_density > disease_density_threshold) {
    return("ORANGE ZONE - Perhatian")
  } else {
    return("GREEN ZONE - Stabil")
  }
}

# Calculate Pareto cumulative percentage
calculate_pareto <- function(data, value_col) {
  total <- sum(data[[value_col]], na.rm = TRUE)
  data %>%
    arrange(desc(!!sym(value_col))) %>%
    mutate(
      cumsum = cumsum(!!sym(value_col)),
      cumulative_pct = cumsum / total * 100
    )
}

# Message for logging
log_message <- function(msg, level = "INFO") {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  cat(sprintf("[%s] %s: %s\n", timestamp, level, msg))
}
