# ============================================================
# LIVESTOCK INTELLIGENCE DASHBOARD
# OLAP Analysis - Kelompok 1 (3SI1) STIS
# R Shiny + Leaflet + sf Spatial Map
# ============================================================
# PERBAIKAN UTAMA:
#  1. SHP tidak terbaca → diganti dengan GeoJSON Indonesia online
#     + fallback ke koordinat centroid manual jika offline
#  2. Normalisasi nama provinsi diperkuat (fuzzy matching)
#  3. Tab Time-Lag Correlation ditambahkan sesuai tujuan proyek
#  4. Disparitas Harga Regional vs Temporal ditambahkan
#  5. Berbagai bug kecil diperbaiki (empty data guard, etc.)
# ============================================================

# ---- INSTALL CHECK ----
packages <- c("shiny","shinydashboard","dplyr","tidyr",
              "ggplot2","plotly","leaflet","sf","scales","DT","shinycssloaders",
              "fresh","htmltools","lubridate","RColorBrewer",
              "rnaturalearth","rnaturalearthdata")

for (pkg in packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg, repos = "https://cloud.r-project.org", quiet = TRUE)
  }
}

library(shiny)
library(shinydashboard)
library(dplyr)
library(tidyr)
library(ggplot2)
library(plotly)
library(leaflet)
library(sf)
library(scales)
library(DT)
library(shinycssloaders)
library(fresh)
library(htmltools)
library(lubridate)
library(RColorBrewer)
library(rnaturalearth)
library(rnaturalearthdata)

# ============================================================
# KONFIGURASI DATA — CSV (untuk deployment shinyapps.io)
# ============================================================
# Cara update data:
#   1. Di komputer lokal, jalankan script export_to_csv.R
#      (atau query manual dan simpan hasilnya sebagai data/olap_cube.csv)
#   2. Overwrite file data/olap_cube.csv
#   3. Re-deploy ke shinyapps.io

CSV_PATH <- "data/olap_cube.csv"

# ============================================================
# PATH SHAPEFILE — ROBUST & PORTABEL
# ============================================================
# Prioritas pencarian:
#   1. File 'Administrasi_Provinsi.shp' di folder yang sama dengan app.R
#   2. Folder 'www/' di dalam folder app.R
#   3. GeoJSON Indonesia dari GitHub (online, tidak butuh file lokal)
#
# Jika semua gagal, peta akan menampilkan bubble map dari centroid.

# ============================================================
# PETA INDONESIA — rnaturalearth (tidak perlu SHP / GeoJSON lokal)
# ============================================================
# Menggunakan package rnaturalearth yang memuat batas administrasi
# Indonesia langsung dari data bawaan R (tidak butuh file eksternal).

# Mapping: nama rnaturalearth → nama resmi BPS (uppercase)
PROV_NAME_MAP <- c(
  "ACEH"                           = "ACEH",
  "NANGGROE ACEH DARUSSALAM"       = "ACEH",
  "SUMATERA UTARA"                 = "SUMATERA UTARA",
  "NORTH SUMATRA"                  = "SUMATERA UTARA",
  "SUMATERA BARAT"                 = "SUMATERA BARAT",
  "WEST SUMATRA"                   = "SUMATERA BARAT",
  "RIAU"                           = "RIAU",
  "KEPULAUAN RIAU"                 = "KEPULAUAN RIAU",
  "RIAU ISLANDS"                   = "KEPULAUAN RIAU",
  "JAMBI"                          = "JAMBI",
  "SUMATERA SELATAN"               = "SUMATERA SELATAN",
  "SOUTH SUMATRA"                  = "SUMATERA SELATAN",
  "BANGKA BELITUNG"                = "KEP. BANGKA BELITUNG",
  "KEPULAUAN BANGKA BELITUNG"      = "KEP. BANGKA BELITUNG",
  "BANGKA-BELITUNG"                = "KEP. BANGKA BELITUNG",
  "BENGKULU"                       = "BENGKULU",
  "LAMPUNG"                        = "LAMPUNG",
  "DKI JAKARTA"                    = "DKI JAKARTA",
  "JAKARTA RAYA"                   = "DKI JAKARTA",   # <--- TAMBAHAN UNTUK RNATURALEARTH
  "JAKARTA"                        = "DKI JAKARTA",
  "JAWA BARAT"                     = "JAWA BARAT",
  "WEST JAVA"                      = "JAWA BARAT",
  "JAWA TENGAH"                    = "JAWA TENGAH",
  "CENTRAL JAVA"                   = "JAWA TENGAH",
  "DI YOGYAKARTA"                  = "DI YOGYAKARTA",
  "DAERAH ISTIMEWA YOGYAKARTA"     = "DI YOGYAKARTA",
  "YOGYAKARTA"                     = "DI YOGYAKARTA",
  "JAWA TIMUR"                     = "JAWA TIMUR",
  "EAST JAVA"                      = "JAWA TIMUR",
  "BANTEN"                         = "BANTEN",
  "BALI"                           = "BALI",
  "NUSA TENGGARA BARAT"            = "NUSA TENGGARA BARAT",
  "WEST NUSA TENGGARA"             = "NUSA TENGGARA BARAT",
  "NUSA TENGGARA TIMUR"            = "NUSA TENGGARA TIMUR",
  "EAST NUSA TENGGARA"             = "NUSA TENGGARA TIMUR",
  "KALIMANTAN BARAT"               = "KALIMANTAN BARAT",
  "WEST KALIMANTAN"                = "KALIMANTAN BARAT",
  "KALIMANTAN TENGAH"              = "KALIMANTAN TENGAH",
  "CENTRAL KALIMANTAN"             = "KALIMANTAN TENGAH",
  "KALIMANTAN SELATAN"             = "KALIMANTAN SELATAN",
  "SOUTH KALIMANTAN"               = "KALIMANTAN SELATAN",
  "KALIMANTAN TIMUR"               = "KALIMANTAN TIMUR",
  "EAST KALIMANTAN"                = "KALIMANTAN TIMUR",
  "KALIMANTAN UTARA"               = "KALIMANTAN UTARA",
  "NORTH KALIMANTAN"               = "KALIMANTAN UTARA",
  "SULAWESI UTARA"                 = "SULAWESI UTARA",
  "NORTH SULAWESI"                 = "SULAWESI UTARA",
  "SULAWESI TENGAH"                = "SULAWESI TENGAH",
  "CENTRAL SULAWESI"               = "SULAWESI TENGAH",
  "SULAWESI SELATAN"               = "SULAWESI SELATAN",
  "SOUTH SULAWESI"                 = "SULAWESI SELATAN",
  "SULAWESI TENGGARA"              = "SULAWESI TENGGARA",
  "SOUTHEAST SULAWESI"             = "SULAWESI TENGGARA",
  "GORONTALO"                      = "GORONTALO",
  "SULAWESI BARAT"                 = "SULAWESI BARAT",
  "WEST SULAWESI"                  = "SULAWESI BARAT",
  "MALUKU"                         = "MALUKU",
  "MALUKU UTARA"                   = "MALUKU UTARA",
  "NORTH MALUKU"                   = "MALUKU UTARA",
  "PAPUA"                          = "PAPUA",
  "PAPUA BARAT"                    = "PAPUA BARAT",
  "WEST PAPUA"                     = "PAPUA BARAT"
)

# Muat batas provinsi Indonesia dari rnaturalearth (tidak perlu internet)
INDONESIA_SF <- tryCatch({
  indo <- ne_states(country = "indonesia", returnclass = "sf")
  indo$PROVINSI <- toupper(trimws(indo$name))
  mapped <- PROV_NAME_MAP[indo$PROVINSI]
  indo$PROVINSI <- ifelse(is.na(mapped), indo$PROVINSI, mapped)
  indo
}, error = function(e) {
  message("[PETA] rnaturalearth gagal: ", e$message)
  NULL
})

# Centroid koordinat fallback jika SHP & GeoJSON tidak tersedia
PROV_CENTROID <- data.frame(
  nama_provinsi = c("ACEH","SUMATERA UTARA","SUMATERA BARAT","RIAU","KEPULAUAN RIAU",
                    "JAMBI","SUMATERA SELATAN","KEP. BANGKA BELITUNG","BENGKULU","LAMPUNG",
                    "DKI JAKARTA","JAWA BARAT","JAWA TENGAH","DI YOGYAKARTA","JAWA TIMUR",
                    "BANTEN","BALI","NUSA TENGGARA BARAT","NUSA TENGGARA TIMUR",
                    "KALIMANTAN BARAT","KALIMANTAN TENGAH","KALIMANTAN SELATAN",
                    "KALIMANTAN TIMUR","KALIMANTAN UTARA",
                    "SULAWESI UTARA","SULAWESI TENGAH","SULAWESI SELATAN",
                    "SULAWESI TENGGARA","GORONTALO","SULAWESI BARAT",
                    "MALUKU","MALUKU UTARA","PAPUA","PAPUA BARAT"),
  lat = c(4.69, 2.11, -0.74, 0.29, 3.94,
          -1.61, -3.31, -2.74, -3.79, -4.56,
          -6.21, -6.92, -7.15, -7.79, -7.54,
          -6.40, -8.34, -8.65, -8.66,
          0.00, -1.68, -3.09,
          1.00, 3.07,
          0.62, -1.43, -3.67,
          -4.15, 0.56, -2.84,
          -3.24, 1.57, -4.27, -1.34),
  lon = c(96.75, 99.07, 100.37, 101.70, 108.14,
          103.61, 104.03, 107.61, 102.34, 105.41,
          106.85, 107.60, 110.14, 110.37, 112.24,
          106.11, 115.09, 116.42, 121.08,
          110.42, 113.92, 115.28,
          116.87, 117.55,
          124.84, 121.44, 119.92,
          122.17, 122.43, 119.37,
          130.14, 127.81, 138.38, 134.05),
  stringsAsFactors = FALSE
)

# ============================================================
# FUNGSI KONEKSI & QUERY
# ============================================================

load_olap_cube <- function() {
  if (!file.exists(CSV_PATH)) {
    stop(paste0("File CSV tidak ditemukan: ", CSV_PATH,
                "\nJalankan export_to_csv.R terlebih dahulu."))
  }
  df <- read.csv(CSV_PATH, stringsAsFactors = FALSE, encoding = "UTF-8")
  # Pastikan tipe kolom yang benar
  df$tahun  <- as.integer(df$tahun)
  df$bulan  <- as.integer(df$bulan)
  df$kuartal <- as.integer(df$kuartal)
  df$supply_risk_index <- as.numeric(df$supply_risk_index)
  df$avg_harga         <- as.numeric(df$avg_harga)
  df$sum_jumlah_sakit  <- as.numeric(df$sum_jumlah_sakit)
  df$sum_jumlah_mati   <- as.numeric(df$sum_jumlah_mati)
  df$sum_vol_mutasi    <- as.numeric(df$sum_vol_mutasi)
  df$populasi_ternak   <- as.numeric(df$populasi_ternak)
  # Pastikan nama provinsi uppercase untuk join peta
  df$nama_provinsi <- toupper(trimws(df$nama_provinsi))
  df
}

# ============================================================
# THEME KUSTOM - Putih & Hijau (Sesuai Logo)
# ============================================================
custom_theme <- create_theme(
  adminlte_color(
    light_blue  = "#1e8449", # Mengubah warna primary default jadi Hijau Logo
    red         = "#c0392b",
    green       = "#27ae60",
    orange      = "#f39c12",
    yellow      = "#f1c40f"
  ),
  adminlte_sidebar(
    width        = "260px",
    dark_bg      = "#ffffff",   # Sidebar Background Putih
    dark_hover_bg= "#eafaf1",   # Warna hijau muda saat menu di-hover
    dark_color   = "#2c3e50"    # Warna teks menu (Abu-abu gelap)
  ),
  adminlte_global(
    content_bg   = "#f8f9fa",   # Background konten abu-abu sangat muda/bersih
    box_bg       = "#ffffff",
    info_box_bg  = "#ffffff"
  )
)

# ============================================================
# HELPER
# ============================================================

alert_color <- function(risk) {
  dplyr::case_when(
    risk >= 0.6 ~ "#c0392b",   # merah  - BAHAYA
    risk >= 0.3 ~ "#d68910",   # orange - WASPADA
    TRUE        ~ "#1e8449"    # hijau  - AMAN
  )
}

# Fungsi label status (dipakai di mutate)
alert_status <- function(risk) {
  dplyr::case_when(
    risk >= 0.6 ~ "BAHAYA",
    risk >= 0.3 ~ "WASPADA",
    TRUE        ~ "AMAN"
  )
}

# Normalisasi nama provinsi untuk fuzzy join dengan peta
normalize_prov <- function(x) {
  x <- toupper(trimws(x))
  # Singkatan umum
  x <- gsub("^D\\.I\\.", "DI",  x)
  x <- gsub("^D\\.K\\.I\\.", "DKI", x)
  x <- gsub("KEP\\.", "KEPULAUAN", x)
  x <- gsub("KEPULAUAN KEPULAUAN", "KEPULAUAN", x)
  x
}

# Coba join berdasarkan mapping dictionary dulu, lalu exact, lalu prefix
join_peta <- function(shp_df, data_df, shp_col = "PROVINSI") {
  shp_df$PROV_KEY_JOIN <- toupper(trimws(shp_df[[shp_col]]))
  # Terapkan mapping
  mapped <- PROV_NAME_MAP[shp_df$PROV_KEY_JOIN]
  shp_df$PROV_KEY_JOIN <- ifelse(is.na(mapped), shp_df$PROV_KEY_JOIN, mapped)
  
  data_df$PROV_KEY_JOIN <- toupper(trimws(data_df$nama_provinsi))
  
  merged <- shp_df %>%
    left_join(data_df, by = "PROV_KEY_JOIN")
  merged
}

# ============================================================
# UI
# ============================================================

ui <- dashboardPage(
  skin = "blue",
  
  # ---- HEADER ----
  dashboardHeader(
    title = tags$span(
      # Memanggil logo dari folder www
      tags$img(src = "logo.png", height = "35px", style = "margin-right:8px; vertical-align:middle; display:inline-block;", onerror = "this.style.display='none'"),
      tags$b("LIVESTOCK", style = "font-size:16px; color:#1e8449; font-weight:800; letter-spacing: 1px;"),
      tags$span(" DASHBOARD", style = "font-size:14px; color:#2c3e50; font-weight:600;")
    ),
    titleWidth = 260,
    tags$li(class = "dropdown",
            tags$div(style = "padding:12px 20px; color:#1e8449; font-size:13px; font-weight:bold;",
                     tags$i(class = "fa fa-leaf"), " Kelompok 1 · 3SI1 · STIS"
            )
    )
  ),
  
  # ---- SIDEBAR ----
  dashboardSidebar(
    width = 260,
    tags$div(
      style = "padding:16px 20px 8px; color:#7fa3c0; font-size:11px; letter-spacing:1.5px; text-transform:uppercase;",
      "Livestock Intelligence"
    ),
    sidebarMenu(
      id = "sidebar",
      menuItem("Beranda & Ringkasan",     tabName = "home",     icon = icon("home")),
      menuItem("Early Warning System",    tabName = "ews",      icon = icon("exclamation-triangle")),
      menuItem("Harga vs Wabah",          tabName = "harga",    icon = icon("chart-line")),
      menuItem("Supply–Demand Gap",       tabName = "gap",      icon = icon("balance-scale")),
      menuItem("Peta Risiko Spasial",     tabName = "peta",     icon = icon("map-marked-alt")),
      menuItem("Dependensi Supply",       tabName = "supply",   icon = icon("sitemap")),
      menuItem("Disparitas Harga",        tabName = "disparitas", icon = icon("dollar-sign")),
      menuItem("OLAP Explorer",           tabName = "olap",     icon = icon("cube"))
    ),
    tags$hr(style = "border-color:#1a3a5c; margin:12px 0;"),
    tags$div(style = "padding:0 16px;",
             tags$p(style = "color:#7fa3c0; font-size:11px; text-transform:uppercase; letter-spacing:1px;",
                    "Filter Global"),
             selectInput("sel_komoditas", "Komoditas",
                         choices = c("Semua", "Sapi", "Ayam"), selected = "Semua", width = "100%"),
             uiOutput("ui_tahun"),
             uiOutput("ui_provinsi")
    ),
    tags$div(
      style = "position:absolute; bottom:12px; left:0; right:0; text-align:center; color:#3d6484; font-size:10px;",
      "TPD · 2026 · Kelompok 1"
    )
  ),
  
  # ---- BODY ----
  dashboardBody(
    use_theme(custom_theme),
    tags$head(
      tags$link(rel = "stylesheet",
                href = "https://fonts.googleapis.com/css2?family=Source+Serif+4:wght@400;600;700&family=IBM+Plex+Sans:wght@400;500;600&display=swap"),
      tags$style(HTML("
        body, .content-wrapper, .main-footer { font-family: 'IBM Plex Sans', sans-serif; }
        h1,h2,h3,h4 { font-family: 'Source Serif 4', serif; }
        
        /* OVERRIDE HEADER & NAVBAR JADI PUTIH */
        .main-header .logo { background: #ffffff !important; border-bottom:1px solid #e9ecef !important; border-right:1px solid #e9ecef !important; }
        .main-header .navbar { background: #ffffff !important; border-bottom:1px solid #e9ecef !important; }
        .main-header .sidebar-toggle { color: #1e8449 !important; }
        .main-header .sidebar-toggle:hover { background: #eafaf1 !important; color: #1e8449 !important; }
        
        /* OVERRIDE SIDEBAR JADI PUTIH & HIJAU */
        .skin-blue .main-sidebar { background: #ffffff !important; border-right:1px solid #e9ecef !important; }
        .skin-blue .sidebar-menu > li > a { color: #2c3e50 !important; font-size:13px; font-weight:500; }
        .skin-blue .sidebar-menu > li > a .fa { color: #1e8449; width:20px; }
        .skin-blue .sidebar-menu > li.active > a,
        .skin-blue .sidebar-menu > li > a:hover { background: #1e8449 !important; color:#ffffff !important; border-radius:6px; margin:0 8px; }
        .skin-blue .sidebar-menu > li.active > a .fa,
        .skin-blue .sidebar-menu > li > a:hover .fa { color: #ffffff !important; }
        
        /* BOX & COMPONENT STYLE */
        .content-wrapper { background: #f8f9fa !important; }
        .box { border-radius:8px; border-top:3px solid #1e8449; box-shadow:0 2px 10px rgba(0,0,0,.05); }
        .box-header { border-bottom:1px solid #e9ecef; padding:12px 16px; }
        .box-title { font-family:'Source Serif 4',serif; font-size:15px; font-weight:600; color:#2c3e50; }
        .info-box { border-radius:8px; box-shadow:0 2px 10px rgba(0,0,0,.05); min-height:90px; }
        .small-box { border-radius:8px; box-shadow:0 2px 10px rgba(0,0,0,.05); }
        
        /* SECTION TITLE (Garis Kiri Hijau) */
        .section-title { font-family:'Source Serif 4',serif; font-size:18px; font-weight:700; color:#2c3e50;
                         border-left:4px solid #1e8449; padding-left:12px; margin:16px 0 12px; }
                         
        table.dataTable { font-size:12px; }
        .dataTables_wrapper .dataTables_paginate .paginate_button.current { background:#1e8449 !important; border-color:#1e8449 !important; color:#fff !important; }
        /* FILTER SIDEBAR — label & select input terlihat di atas background putih */
        .main-sidebar .form-group label { color: #2c3e50 !important; font-size:12px; font-weight:600; }
        .main-sidebar .selectize-input { background:#f8f9fa !important; border:1px solid #ced4da !important; color:#2c3e50 !important; border-radius:5px; }
        .main-sidebar .selectize-input.focus { border-color:#1e8449 !important; box-shadow:0 0 0 2px rgba(30,132,73,.15) !important; }
        .main-sidebar .selectize-dropdown { border:1px solid #ced4da !important; background:#ffffff !important; color:#2c3e50 !important; }
        .main-sidebar .selectize-dropdown .option:hover { background:#eafaf1 !important; color:#1e8449 !important; }
        .main-sidebar p { color: #2c3e50 !important; }
      "))
    ),
    
    tabItems(
      
      # =========================================================
      # TAB 1: BERANDA
      # =========================================================
      tabItem(tabName = "home",
              fluidRow(column(12, tags$div(class="section-title", "Ringkasan Eksekutif — Livestock Intelligence"))),
              fluidRow(
                valueBoxOutput("kpi_risk_avg",  width=3),
                valueBoxOutput("kpi_kritis",    width=3),
                valueBoxOutput("kpi_waspada",   width=3),
                valueBoxOutput("kpi_aman",      width=3)
              ),
              fluidRow(
                column(6, box(width=NULL, title="Distribusi Zona Risiko per Provinsi",
                              withSpinner(plotlyOutput("home_risk_dist", height="280px"), color="#1a3a5c"))),
                column(6, box(width=NULL, title="Tren Risk Index Nasional per Kuartal",
                              withSpinner(plotlyOutput("home_trend", height="280px"), color="#1a3a5c")))
              ),
              fluidRow(
                column(12, box(width=NULL, title="Status Alert Terkini (Bulan Terakhir)",
                               withSpinner(DTOutput("home_alert_table"), color="#1a3a5c")))
              )
      ),
      
      # =========================================================
      # TAB 2: EARLY WARNING SYSTEM
      # =========================================================
      tabItem(tabName = "ews",
              fluidRow(column(12, tags$div(class="section-title", "Early Warning System — Supply Risk Index"))),
              fluidRow(
                column(6, box(width=NULL, title="Top 10 Provinsi Risiko Tertinggi (All-Time Average)",
                              withSpinner(plotlyOutput("ews_top10", height="380px"), color="#1a3a5c"))),
                column(6, box(width=NULL, title="Timeline Risiko — Top 5 Provinsi",
                              withSpinner(plotlyOutput("ews_timeline", height="380px"), color="#1a3a5c")))
              ),
              fluidRow(
                column(12, box(width=NULL, title="Heatmap Risiko: Provinsi × Bulan",
                               withSpinner(plotlyOutput("ews_heatmap", height="460px"), color="#1a3a5c")))
              )
      ),
      
      # =========================================================
      # TAB 3: HARGA vs WABAH  (termasuk Time-Lag Correlation)
      # =========================================================
      tabItem(tabName = "harga",
              fluidRow(column(12, tags$div(class="section-title", "Harga vs Wabah — Korelasi & Time-Lag Analysis"))),
              
              # --- BAGIAN UTAMA: TIME-LAG CORRELATION ---
              fluidRow(
                column(12,
                       box(width=NULL,
                           tags$div(class="alert-banner alert-waspada",
                                    tags$b("Metode Cross-Spatial:"),
                                    " Wabah diambil dari PROVINSI PRODUSEN (hulu) dan harga diambil dari PROVINSI KONSUMEN (hilir). ",
                                    "Ini membuktikan apakah gangguan rantai pasok di daerah asal merambat ke harga di pasar tujuan — ",
                                    "dan berapa bulan jedanya (Golden Window)."
                           )
                       )
                )
              ),
              fluidRow(
                column(4,
                       box(width=NULL, title="Pengaturan Time-Lag",
                           selectInput("lag_komoditas", "Komoditas",
                                       choices = c("Sapi", "Ayam"), selected = "Sapi"),
                           selectInput("lag_metric_x", "Variabel Wabah (Hulu)",
                                       choices = c("Jumlah Sakit" = "sum_jumlah_sakit",
                                                   "Jumlah Mati"  = "sum_jumlah_mati"),
                                       selected = "sum_jumlah_sakit"),
                           sliderInput("lag_max", "Lag Maks (bulan)", min=2, max=12, value=6, step=1),
                           tags$hr(),
                           tags$p(tags$b("Provinsi Hulu (Produsen):"),
                                  style="font-size:12px; margin-bottom:4px;"),
                           uiOutput("lag_ui_hulu"),
                           tags$p(tags$b("Provinsi Hilir (Konsumen):"),
                                  style="font-size:12px; margin-top:8px; margin-bottom:4px;"),
                           uiOutput("lag_ui_hilir"),
                           tags$hr(),
                           tags$p(tags$b("Korelasi Tertinggi:"), style="font-size:12px;"),
                           verbatimTextOutput("lag_peak_info")
                       )
                ),
                column(8,
                       box(width=NULL,
                           title="Korelasi Pearson per Lag — Wabah Hulu (t) → Harga Hilir (t+lag)",
                           withSpinner(plotlyOutput("lag_bar", height="340px"), color="#1a3a5c")),
                       box(width=NULL,
                           title="Overlay Z-Score: Wabah Hulu vs Harga Hilir (digeser lag terbaik)",
                           withSpinner(plotlyOutput("lag_overlay", height="300px"), color="#1a3a5c"))
                )
              ),
              
              # --- BAGIAN BAWAH: GRAFIK PELENGKAP ---
              fluidRow(
                valueBoxOutput("corr_sapi", width=6),
                valueBoxOutput("corr_ayam", width=6)
              ),
              fluidRow(
                column(6, box(width=NULL, title="Scatter: Harga vs Jumlah Sakit (per Komoditas)",
                              withSpinner(plotlyOutput("harga_scatter", height="320px"), color="#1a3a5c"))),
                column(6, box(width=NULL, title="Distribusi Harga per Kuartal (Box Plot)",
                              withSpinner(plotlyOutput("harga_boxplot", height="320px"), color="#1a3a5c")))
              )
      ),
      
      # =========================================================
      # TAB 5: SUPPLY–DEMAND GAP
      # =========================================================
      tabItem(tabName = "gap",
              
              fluidRow(
                column(12, tags$div(class="section-title", "Supply–Demand Gap Analysis"))
              ),
              
              # KPI
              fluidRow(
                valueBoxOutput("gap_surplus_mo",   width=3),
                valueBoxOutput("gap_deficit_mo",   width=3),
                valueBoxOutput("gap_avg_logistik", width=3),
                valueBoxOutput("gap_avg_konsumsi", width=3)
              ),
              
              # 🔥 MAIN CHART (WAJIB)
              fluidRow(
                column(12,
                       box(width=NULL,
                           title="Supply vs Demand (Konsumsi Sapi)",
                           withSpinner(plotlyOutput("gap_supply_demand", height="350px"),
                                       color="#1a3a5c")
                       )
                )
              ),
              
              # DETAIL ANALISIS
              fluidRow(
                column(6,
                       box(width=NULL,
                           title="Top Provinsi Deficit Terbesar",
                           withSpinner(plotlyOutput("gap_deficit_prov", height="320px"),
                                       color="#1a3a5c")
                       )
                ),
                column(6,
                       box(width=NULL,
                           title="Gap Konsumsi: Surplus vs Defisit",
                           withSpinner(plotlyOutput("gap_konsumsi", height="320px"),
                                       color="#1a3a5c")
                       )
                )
              )
      ),
      
      # =========================================================
      # TAB 6: PETA RISIKO SPASIAL
      # =========================================================
      tabItem(tabName = "peta",
              fluidRow(column(12, tags$div(class="section-title", "Peta Risiko Spasial — Administrasi Provinsi Indonesia"))),
              uiOutput("peta_status_banner"),
              fluidRow(
                column(3,
                       box(width=NULL, title="Pengaturan Peta",
                           selectInput("peta_komoditas","Komoditas",
                                       choices=c("Semua","Sapi","Ayam"), selected="Semua"),
                           uiOutput("peta_tahun_ui"),
                           selectInput("peta_metric","Metrik",
                                       choices=c("Supply Risk Index"  = "supply_risk_index",
                                                 "Harga Rata-rata"    = "avg_harga",
                                                 "Jumlah Sakit"       = "sum_jumlah_sakit",
                                                 "Vol Mutasi"         = "sum_vol_mutasi")),
                           tags$hr(),
                           uiOutput("peta_legenda_ui")
                       )
                ),
                column(9,
                       box(width=NULL, title="Peta Choropleth / Bubble Risk Index per Provinsi",
                           withSpinner(leafletOutput("peta_map", height="540px"), color="#1a3a5c"))
                )
              ),
              fluidRow(
                column(12, box(width=NULL, title="Bubble Chart: Populasi Ternak vs Disease Density",
                               withSpinner(plotlyOutput("peta_bubble", height="360px"), color="#1a3a5c")))
              )
      ),
      
      # =========================================================
      # TAB 7: DEPENDENSI SUPPLY
      # =========================================================
      tabItem(tabName = "supply",
              fluidRow(column(12, tags$div(class="section-title","Ketergantungan & Dependensi Supply"))),
              fluidRow(
                column(12, box(width=NULL,
                               tags$p(tags$b("Filter Provinsi (Pareto & Treemap):"), style="font-size:12px; margin-bottom:4px;"),
                               uiOutput("supply_prov_filter_ui")
                ))
              ),
              fluidRow(
                column(6, box(width=NULL, title="Pareto Chart — Konsentrasi Pasokan Nasional",
                              withSpinner(plotlyOutput("supply_pareto", height="380px"), color="#1a3a5c"))),
                column(6, box(width=NULL, title="Proporsi Supply per Provinsi (Treemap)",
                              withSpinner(plotlyOutput("supply_treemap", height="380px"), color="#1a3a5c")))
              ),
              fluidRow(
                column(12, box(width=NULL, title="Provinsi Rentan: Supply ≥ 10% Nasional & Risk ≥ 0.3",
                               withSpinner(DTOutput("supply_vulner_table"), color="#1a3a5c")))
              )
      ),
      
      # =========================================================
      # TAB 8: DISPARITAS HARGA REGIONAL VS TEMPORAL (BARU)
      # =========================================================
      tabItem(tabName = "disparitas",
              fluidRow(column(12, tags$div(class="section-title","Disparitas Harga — Regional vs Temporal"))),
              fluidRow(
                column(12,
                       box(width=NULL,
                           tags$div(class="alert-banner alert-aman",
                                    tags$b("Insight Utama:"), " Masalah utama harga daging Indonesia bukan KAPAN (waktu/musiman), ",
                                    "tetapi DI MANA (disparitas antar-daerah). Visualisasi ini membuktikan hal tersebut secara empiris."
                           )
                       )
                )
              ),
              fluidRow(
                column(6, box(width=NULL, title="Strip/Jitter Plot: Harga per Bulan per Provinsi",
                              withSpinner(plotlyOutput("disp_strip", height="380px"), color="#1a3a5c"))),
                column(6, box(width=NULL, title="CV Harga (Koefisien Variasi) — Disparitas Antar Provinsi",
                              withSpinner(plotlyOutput("disp_cv_bar", height="380px"), color="#1a3a5c")))
              ),
              fluidRow(
                column(12, box(width=NULL, title="Heatmap Harga: Provinsi × Bulan (Per Komoditas)",
                               withSpinner(plotlyOutput("disp_heatmap", height="460px"), color="#1a3a5c")))
              )
      ),
      
      # =========================================================
      # TAB 9: OLAP EXPLORER
      # =========================================================
      tabItem(tabName = "olap",
              fluidRow(column(12, tags$div(class="section-title","OLAP Explorer — Slice · Dice · Roll-up · Drill-down"))),
              fluidRow(
                column(12,
                       box(width=NULL,
                           fluidRow(
                             column(3,
                                    tags$p(tags$b("Pilih Operasi OLAP"), style="font-size:12px;color:#1a3a5c;"),
                                    selectInput("olap_op","Operasi",
                                                choices=c("Slice — Komoditas"   ="slice_kom",
                                                          "Slice — Provinsi"    ="slice_prov",
                                                          "Slice — Tahun"       ="slice_thn",
                                                          "Dice — Multi Filter" ="dice",
                                                          "Roll-up — per Tahun" ="rollup_thn",
                                                          "Roll-up — per Prov"  ="rollup_prov",
                                                          "Drill-down — Bulanan"="drilldown"))
                             ),
                             column(3, uiOutput("olap_filter1")),
                             column(3, uiOutput("olap_filter2")),
                             column(3, uiOutput("olap_filter3"))
                           )
                       )
                )
              ),
              fluidRow(
                column(12,
                       box(width=NULL, title="Hasil OLAP",
                           withSpinner(DTOutput("olap_result"), color="#1a3a5c"),
                           tags$br(),
                           withSpinner(plotlyOutput("olap_chart", height="340px"), color="#1a3a5c")
                       )
                )
              )
      )
      
    ) # end tabItems
  ) # end dashboardBody
)

# ============================================================
# SERVER
# ============================================================

server <- function(input, output, session) {
  
  # ---- Load Data ----
  cube_raw <- reactive({
    withProgress(message="Memuat data DWH...", {
      load_olap_cube()
    })
  })
  
  # ---- Apply Global Filter ----
  cube <- reactive({
    df <- cube_raw()
    if (!is.null(input$sel_komoditas) && input$sel_komoditas != "Semua")
      df <- df %>% filter(nama_komoditas == input$sel_komoditas)
    if (!is.null(input$filter_tahun) && input$filter_tahun != "Semua")
      df <- df %>% filter(tahun == as.integer(input$filter_tahun))
    if (!is.null(input$filter_provinsi) && input$filter_provinsi != "Semua")
      df <- df %>% filter(nama_provinsi == input$filter_provinsi)
    df
  })
  
  # ---- Dynamic Filters ----
  output$ui_tahun <- renderUI({
    df <- cube_raw()
    selectInput("filter_tahun","Tahun",
                choices=c("Semua", sort(unique(df$tahun), decreasing=TRUE)),
                selected="Semua", width="100%")
  })
  
  output$ui_provinsi <- renderUI({
    df <- cube_raw()
    selectInput("filter_provinsi","Provinsi",
                choices=c("Semua", sort(unique(df$nama_provinsi))),
                selected="Semua", width="100%")
  })
  
  # ---- Tahun filter khusus peta ----
  output$peta_tahun_ui <- renderUI({
    thn <- sort(unique(cube_raw()$tahun), decreasing=TRUE)
    selectInput("peta_tahun","Tahun", choices=thn, selected=thn[1])
  })
  
  output$peta_legenda_ui <- renderUI({
    metric <- input$peta_metric
    if (is.null(metric) || metric == "supply_risk_index") {
      tagList(
        tags$p(tags$b("Legenda Zona:"), style="font-size:12px;"),
        tags$div(style="font-size:12px; line-height:2;",
                 tags$span(style="background:#c0392b;color:#fff;padding:2px 8px;border-radius:4px;","BAHAYA ≥ 0.6"),
                 tags$br(),
                 tags$span(style="background:#d68910;color:#fff;padding:2px 8px;border-radius:4px;","WASPADA ≥ 0.3"),
                 tags$br(),
                 tags$span(style="background:#1e8449;color:#fff;padding:2px 8px;border-radius:4px;","AMAN < 0.3")
        )
      )
    } else if (metric == "avg_harga") {
      tagList(
        tags$p(tags$b("Legenda Warna:"), style="font-size:12px;"),
        tags$div(style="font-size:12px; color:#555;",
                 "Gradasi biru: semakin gelap = harga rata-rata lebih tinggi"
        )
      )
    } else if (metric == "sum_jumlah_sakit") {
      tagList(
        tags$p(tags$b("Legenda Warna:"), style="font-size:12px;"),
        tags$div(style="font-size:12px; color:#555;",
                 "Gradasi merah: semakin gelap = jumlah hewan sakit lebih banyak"
        )
      )
    } else if (metric == "sum_vol_mutasi") {
      tagList(
        tags$p(tags$b("Legenda Warna:"), style="font-size:12px;"),
        tags$div(style="font-size:12px; color:#555;",
                 "Gradasi ungu: semakin gelap = volume mutasi lebih tinggi"
        )
      )
    }
  })
  
  # ===========================================================
  # TAB 1: BERANDA
  # ===========================================================
  
  output$kpi_risk_avg <- renderValueBox({
    avg <- mean(cube()$supply_risk_index, na.rm=TRUE)
    col <- if (avg >= 0.6) "red" else if (avg >= 0.3) "orange" else "green"
    valueBox(round(avg,3), "Rata-rata Risk Index", icon=icon("thermometer-half"), color=col)
  })
  
  output$kpi_kritis <- renderValueBox({
    n <- sum(cube()$supply_risk_index >= 0.6, na.rm=TRUE)
    valueBox(format(n, big.mark="."), "Observasi BAHAYA (≥0.6)", icon=icon("times-circle"), color="red")
  })
  
  output$kpi_waspada <- renderValueBox({
    n <- sum(cube()$supply_risk_index >= 0.3 & cube()$supply_risk_index < 0.6, na.rm=TRUE)
    valueBox(format(n, big.mark="."), "Observasi WASPADA (0.3–0.6)", icon=icon("exclamation-circle"), color="orange")
  })
  
  output$kpi_aman <- renderValueBox({
    n <- sum(cube()$supply_risk_index < 0.3, na.rm=TRUE)
    valueBox(format(n, big.mark="."), "Observasi AMAN (<0.3)", icon=icon("check-circle"), color="green")
  })
  
  output$home_risk_dist <- renderPlotly({
    df <- cube() %>%
      group_by(nama_provinsi) %>%
      summarise(avg_risk=mean(supply_risk_index,na.rm=TRUE),.groups="drop") %>%
      mutate(zona=alert_status(avg_risk)) %>%
      count(zona)
    
    colors <- c("BAHAYA"="#c0392b","WASPADA"="#d68910","AMAN"="#1e8449")
    validate(need(nrow(df)>0,"Data kosong."))
    plot_ly(df, labels=~zona, values=~n, type="pie",
            marker=list(colors=colors[df$zona]),
            textinfo="label+percent",
            hovertemplate="%{label}: %{value} provinsi<extra></extra>") %>%
      layout(showlegend=TRUE, legend=list(font=list(size=11)),
             margin=list(t=0,b=0))
  })
  
  output$home_trend <- renderPlotly({
    df <- cube() %>%
      group_by(tahun,kuartal) %>%
      summarise(avg_risk=mean(supply_risk_index,na.rm=TRUE),.groups="drop") %>%
      mutate(periode=paste0(tahun," Q",kuartal))
    
    validate(need(nrow(df)>0,"Data kosong."))
    # Hitung range Y otomatis: dari 0 sampai sedikit di atas nilai max data
    # sehingga perbedaan antar titik terlihat jelas
    y_ceil <- 0.1  # range Y tetap 0.05 - 0.1
    
    plot_ly(df, x=~periode, y=~avg_risk, type="scatter", mode="lines+markers",
            line=list(color="#1a3a5c",width=2.5),
            marker=list(color="#1a3a5c",size=7),
            hovertemplate="%{x}: %{y:.3f}<extra></extra>") %>%
      layout(xaxis=list(title="",tickangle=-45,tickfont=list(size=10)),
             yaxis=list(title="Risk Index", range=c(0.05, y_ceil)),
             margin=list(b=80), showlegend=TRUE,
             shapes=list(
               list(type="line", x0=0, x1=1, xref="paper", y0=0.3, y1=0.3,
                    line=list(dash="dot", color="#d68910", width=1.5)),
               list(type="line", x0=0, x1=1, xref="paper", y0=0.6, y1=0.6,
                    line=list(dash="dot", color="#c0392b", width=1.5))
             ),
             annotations=list(
               list(x=1, y=0.3, xref="paper", yref="y", text="Waspada",
                    showarrow=FALSE, font=list(size=9,color="#d68910"), xanchor="right"),
               list(x=1, y=0.6, xref="paper", yref="y", text="Bahaya",
                    showarrow=FALSE, font=list(size=9,color="#c0392b"), xanchor="right")
             ))
  })
  
  output$home_alert_table <- renderDT({
    df <- cube() %>%
      group_by(nama_provinsi) %>%
      filter(waktu_key==max(waktu_key)) %>%
      summarise(risk=round(mean(supply_risk_index,na.rm=TRUE),4),
                avg_harga=round(mean(avg_harga,na.rm=TRUE),0),
                sakit=sum(sum_jumlah_sakit,na.rm=TRUE),
                .groups="drop") %>%
      mutate(Status=alert_status(risk)) %>%
      arrange(desc(risk)) %>%
      rename(Provinsi=nama_provinsi,`Risk Index`=risk,
             `Harga Rata-rata`=avg_harga,`Jml Sakit`=sakit)
    
    datatable(df, options=list(pageLength=10,scrollX=TRUE),
              rownames=FALSE, class="stripe hover") %>%
      formatStyle("Status",
                  backgroundColor=styleEqual(
                    c("BAHAYA","WASPADA","AMAN"),
                    c("#fdecea","#fef5ec","#eafaf1")),
                  color=styleEqual(
                    c("BAHAYA","WASPADA","AMAN"),
                    c("#c0392b","#d68910","#1e8449")),
                  fontWeight="bold")
  })
  
  # ===========================================================
  # TAB 2: EWS
  # ===========================================================
  
  output$ews_top10 <- renderPlotly({
    df <- cube() %>%
      group_by(nama_provinsi) %>%
      summarise(avg_risk=mean(supply_risk_index,na.rm=TRUE),.groups="drop") %>%
      arrange(desc(avg_risk)) %>% head(10) %>%
      mutate(nama_provinsi=factor(nama_provinsi,levels=rev(nama_provinsi)),
             warna=case_when(avg_risk>=0.6~"#c0392b",avg_risk>=0.3~"#d68910",TRUE~"#1e8449"))
    
    validate(need(nrow(df)>0,"Data kosong."))
    plot_ly(df, x=~avg_risk, y=~nama_provinsi, type="bar", orientation="h",
            marker=list(color=~warna),
            hovertemplate="%{y}: %{x:.4f}<extra></extra>") %>%
      add_lines(x=c(0.3,0.3), y=c(-0.5,9.5),
                line=list(dash="dot",color="#d68910",width=1.5),
                name="Waspada",showlegend=TRUE) %>%
      add_lines(x=c(0.6,0.6), y=c(-0.5,9.5),
                line=list(dash="dot",color="#c0392b",width=1.5),
                name="Bahaya",showlegend=TRUE) %>%
      layout(xaxis=list(title="Avg Supply Risk Index",range=c(0,1)),
             yaxis=list(title=""),margin=list(l=140))
  })
  
  output$ews_timeline <- renderPlotly({
    top5 <- cube() %>%
      group_by(nama_provinsi) %>%
      summarise(avg_risk=mean(supply_risk_index,na.rm=TRUE),.groups="drop") %>%
      arrange(desc(avg_risk)) %>% head(5) %>% pull(nama_provinsi)
    
    df <- cube() %>%
      filter(nama_provinsi %in% top5) %>%
      group_by(tahun,bulan,nama_provinsi) %>%
      summarise(risk=mean(supply_risk_index,na.rm=TRUE),.groups="drop") %>%
      mutate(periode = paste0(tahun, "/", sprintf("%02d", bulan)))
    
    validate(need(nrow(df)>0,"Data tidak cukup untuk filter ini."))
    
    # Ambil semua periode unik untuk sumbu x
    all_periods <- sort(unique(df$periode))
    
    plot_ly() %>%
      # Plot satu trace per provinsi
      { fig <- .
      for (prov in top5) {
        d <- df %>% filter(nama_provinsi == prov)
        fig <- fig %>% add_trace(
          data     = d,
          x        = ~periode,
          y        = ~risk,
          type     = "scatter",
          mode     = "lines+markers",
          name     = prov,
          hovertemplate = paste0(prov, " %{x}: %{y:.4f}<extra></extra>")
        )
      }
      fig
      } %>%
      layout(
        xaxis  = list(title="Periode", tickangle=-45, tickfont=list(size=8),
                      categoryorder="array", categoryarray=all_periods),
        yaxis  = list(title="Risk Index", range=c(0,1)),
        shapes = list(
          # Garis threshold Waspada (0.3)
          list(type="line", x0=0, x1=1, xref="paper",
               y0=0.3, y1=0.3,
               line=list(dash="dot", color="#d68910", width=1.5)),
          # Garis threshold Bahaya (0.6)
          list(type="line", x0=0, x1=1, xref="paper",
               y0=0.6, y1=0.6,
               line=list(dash="dot", color="#c0392b", width=1.5))
        ),
        annotations = list(
          list(x=1, y=0.3, xref="paper", yref="y",
               text="Waspada", showarrow=FALSE,
               font=list(size=9, color="#d68910"), xanchor="right"),
          list(x=1, y=0.6, xref="paper", yref="y",
               text="Bahaya", showarrow=FALSE,
               font=list(size=9, color="#c0392b"), xanchor="right")
        ),
        legend = list(orientation="h", y=-0.30)
      )
  })
  
  output$ews_heatmap <- renderPlotly({
    df <- cube() %>%
      group_by(nama_provinsi,tahun,bulan) %>%
      summarise(risk=mean(supply_risk_index,na.rm=TRUE),.groups="drop") %>%
      mutate(periode=paste0(tahun,"/",sprintf("%02d",bulan)))
    
    validate(need(nrow(df)>0,"Data kosong."))
    mat <- df %>%
      select(nama_provinsi,periode,risk) %>%
      tidyr::pivot_wider(names_from=periode,values_from=risk,values_fn=mean)
    
    prov_names <- mat$nama_provinsi
    mat_vals   <- as.matrix(mat[,-1])
    
    plot_ly(z=mat_vals, x=colnames(mat_vals), y=prov_names,
            type="heatmap",
            colorscale=list(c(0,"#1e8449"),c(0.3,"#f9e79f"),c(0.5,"#d35400"),c(1,"#c0392b")),
            zmin=0, zmax=1,
            hovertemplate="%{y}<br>%{x}: %{z:.4f}<extra></extra>") %>%
      layout(xaxis=list(tickangle=-90,tickfont=list(size=8)),
             yaxis=list(tickfont=list(size=9)))
  })
  
  # ===========================================================
  # TAB 3: HARGA vs WABAH
  # ===========================================================
  
  corr_df <- reactive({
    df <- cube_raw() %>%
      group_by(tahun,bulan,nama_komoditas) %>%
      summarise(avg_harga=mean(avg_harga,na.rm=TRUE),
                sum_sakit=sum(sum_jumlah_sakit,na.rm=TRUE),.groups="drop")
    lapply(c("Sapi","Ayam"), function(k) {
      d <- df %>% filter(nama_komoditas==k) %>% drop_na(avg_harga,sum_sakit)
      if (nrow(d)>2) {
        ct <- cor.test(d$avg_harga, d$sum_sakit)
        data.frame(komoditas=k, r=ct$estimate, p=ct$p.value)
      }
    }) %>% bind_rows()
  })
  
  output$corr_sapi <- renderValueBox({
    r <- corr_df() %>% filter(komoditas=="Sapi") %>% pull(r)
    p <- corr_df() %>% filter(komoditas=="Sapi") %>% pull(p)
    if (length(r)==0) r <- 0; if (length(p)==0) p <- 1
    col <- if (abs(r)>=0.7) "red" else if (abs(r)>=0.5) "orange" else "blue"
    lbl <- if (p<0.05) "signifikan" else "tidak signifikan"
    valueBox(round(r,3), paste0("Korelasi Sapi (",lbl,")"), icon=icon("cow"), color=col)
  })
  
  output$corr_ayam <- renderValueBox({
    r <- corr_df() %>% filter(komoditas=="Ayam") %>% pull(r)
    p <- corr_df() %>% filter(komoditas=="Ayam") %>% pull(p)
    if (length(r)==0) r <- 0; if (length(p)==0) p <- 1
    col <- if (abs(r)>=0.7) "red" else if (abs(r)>=0.5) "orange" else "blue"
    lbl <- if (p<0.05) "signifikan" else "tidak signifikan"
    valueBox(round(r,3), paste0("Korelasi Ayam (",lbl,")"), icon=icon("drumstick-bite"), color=col)
  })
  
  output$harga_scatter <- renderPlotly({
    df <- cube() %>%
      group_by(tahun,bulan,nama_komoditas) %>%
      summarise(avg_harga=mean(avg_harga,na.rm=TRUE),
                sum_sakit=sum(sum_jumlah_sakit,na.rm=TRUE),.groups="drop") %>%
      drop_na()
    validate(need(nrow(df)>0,"Data kosong."))
    plot_ly(df, x=~sum_sakit, y=~avg_harga, color=~nama_komoditas,
            type="scatter", mode="markers",
            marker=list(size=8,opacity=0.7),
            colors=c("#1a3a5c","#c0392b"),
            hovertemplate="%{x} sakit → Rp %{y:,.0f}<extra></extra>") %>%
      layout(xaxis=list(title="Jumlah Sakit"),
             yaxis=list(title="Harga (Rp)",tickformat=","))
  })
  
  output$harga_boxplot <- renderPlotly({
    df <- cube()
    validate(need(nrow(df)>0,"Data kosong."))
    plot_ly(df, x=~paste0("Q",kuartal), y=~avg_harga, color=~nama_komoditas,
            type="box", colors=c("#1a3a5c","#c0392b")) %>%
      layout(xaxis=list(title="Kuartal"),
             yaxis=list(title="Harga (Rp)",tickformat=","),
             boxmode="group")
  })
  
  # ===========================================================
  # TAB 4: TIME-LAG CORRELATION — Cross-Spatial
  # ===========================================================
  
  # Default provinsi hulu & hilir (sama seperti kode Python)
  DEFAULT_HULU  <- c("JAWA TIMUR", "NUSA TENGGARA BARAT", "NUSA TENGGARA TIMUR")
  DEFAULT_HILIR <- c("DKI JAKARTA", "JAWA BARAT", "BANTEN")
  
  # Dynamic UI: pilih provinsi hulu (multi-select)
  output$lag_ui_hulu <- renderUI({
    semua_prov <- sort(unique(cube_raw()$nama_provinsi))
    # Preset default yang ada di data
    default_val <- intersect(DEFAULT_HULU, semua_prov)
    if (length(default_val)==0) default_val <- semua_prov[1:min(3,length(semua_prov))]
    selectInput("lag_prov_hulu", NULL,
                choices  = semua_prov,
                selected = default_val,
                multiple = TRUE,
                width    = "100%")
  })
  
  # Dynamic UI: pilih provinsi hilir (multi-select)
  output$lag_ui_hilir <- renderUI({
    semua_prov <- sort(unique(cube_raw()$nama_provinsi))
    default_val <- intersect(DEFAULT_HILIR, semua_prov)
    if (length(default_val)==0) default_val <- semua_prov[1:min(3,length(semua_prov))]
    selectInput("lag_prov_hilir", NULL,
                choices  = semua_prov,
                selected = default_val,
                multiple = TRUE,
                width    = "100%")
  })
  
  # Helper: siapkan data wabah hulu & harga hilir (cross-spatial)
  lag_base_data <- reactive({
    req(input$lag_prov_hulu, input$lag_prov_hilir, input$lag_komoditas, input$lag_metric_x)
    kom  <- input$lag_komoditas
    xcol <- input$lag_metric_x
    raw  <- cube_raw() %>% filter(nama_komoditas == kom)
    
    # Wabah dari provinsi HULU — agregasi SUM per bulan (sama seperti Python)
    wabah_hulu <- raw %>%
      filter(nama_provinsi %in% input$lag_prov_hulu) %>%
      group_by(tahun, bulan) %>%
      summarise(x_wabah = sum(.data[[xcol]], na.rm=TRUE), .groups="drop")
    
    # Harga dari provinsi HILIR — agregasi MEAN per bulan
    harga_hilir <- raw %>%
      filter(nama_provinsi %in% input$lag_prov_hilir) %>%
      group_by(tahun, bulan) %>%
      summarise(y_harga = mean(avg_harga, na.rm=TRUE), .groups="drop")
    
    # Merge berdasarkan tahun-bulan
    df <- inner_join(wabah_hulu, harga_hilir, by=c("tahun","bulan")) %>%
      arrange(tahun, bulan) %>%
      mutate(t       = row_number(),
             periode = paste0(tahun, "/", sprintf("%02d", bulan)))
    df
  })
  
  # Hitung korelasi Pearson per lag (0 s/d lag_max)
  lag_corr_df <- reactive({
    df   <- lag_base_data()
    lmax <- req(input$lag_max)
    validate(need(nrow(df) > lmax + 2, "Data terlalu sedikit untuk lag yang dipilih."))
    
    hasil <- lapply(0:lmax, function(lg) {
      # Sama dengan Python: harga di-shift -lag (artinya wabah sekarang vs harga masa depan)
      n <- nrow(df)
      if (n - lg < 5) return(NULL)
      d <- data.frame(
        wabah = df$x_wabah[1:(n - lg)],
        harga = df$y_harga[(lg + 1):n]
      ) %>% tidyr::drop_na()
      if (nrow(d) < 5) return(NULL)
      ct <- cor.test(d$wabah, d$harga)
      data.frame(lag = lg,
                 r   = as.numeric(ct$estimate),
                 p   = ct$p.value)
    })
    bind_rows(hasil)
  })
  
  output$lag_bar <- renderPlotly({
    df <- lag_corr_df()
    validate(need(nrow(df) > 0, "Data tidak cukup untuk analisis lag."))
    
    # Cari lag dengan |r| terbesar → warnai merah (seperti Python hardcode 'red' di lag tertinggi)
    peak_idx <- which.max(abs(df$r))
    
    df <- df %>%
      mutate(
        # Signifikan biru tua, peak = merah, tidak signifikan = abu
        warna = case_when(
          row_number() == peak_idx          ~ "#c0392b",   # lag terbaik → merah
          p < 0.05 & r > 0                  ~ "#1a3a5c",   # signifikan positif → biru
          p < 0.05 & r < 0                  ~ "#d35400",   # signifikan negatif → oranye
          TRUE                              ~ "#adb5bd"    # tidak signifikan → abu
        ),
        label_lag = paste0("Lag ", lag),
        label_txt = paste0("r = ", round(r,3), "  |  p = ", round(p,4),
                           ifelse(p < 0.05, " ✓ signifikan", ""))
      )
    
    plot_ly(df,
            x    = ~label_lag,
            y    = ~r,
            type = "bar",
            marker = list(color = ~warna),
            text   = ~round(r, 2),
            textposition = "outside",
            hovertemplate = paste0(
              "<b>%{x}</b><br>",
              "Korelasi r = %{y:.3f}<br>",
              "%{customdata}<extra></extra>"
            ),
            customdata = ~label_txt
    ) %>%
      layout(
        xaxis = list(title="Lag (Wabah Hulu → Harga Hilir)", categoryorder="array",
                     categoryarray=paste0("Lag ", 0:max(df$lag))),
        yaxis = list(title="Korelasi Pearson (r)", range=c(-1, 1)),
        bargap = 0.3,
        shapes = list(
          list(type="line", x0=0, x1=1, xref="paper", y0=0, y1=0,
               line=list(color="black", width=0.8, dash="dash"))
        ),
        annotations = list(list(
          x=df$label_lag[peak_idx], y=df$r[peak_idx] + sign(df$r[peak_idx])*0.08,
          text=paste0("Golden Window\n(Lag ",df$lag[peak_idx]," bln)"),
          showarrow=TRUE, arrowhead=2, arrowcolor="#c0392b",
          font=list(size=10, color="#c0392b")
        ))
      )
  })
  
  output$lag_peak_info <- renderText({
    df <- lag_corr_df()
    if (nrow(df)==0) return("Data tidak cukup.")
    peak <- df %>% arrange(desc(abs(r))) %>% slice(1)
    hulu_str  <- paste(input$lag_prov_hulu,  collapse=", ")
    hilir_str <- paste(input$lag_prov_hilir, collapse=", ")
    paste0(
      "Hulu  : ", hulu_str,  "\n",
      "Hilir : ", hilir_str, "\n\n",
      "Golden Window : ", peak$lag, " bulan\n",
      "Korelasi (r)  : ", round(peak$r, 3), "\n",
      "p-value       : ", round(peak$p, 4), "\n",
      "Status        : ", ifelse(peak$p < 0.05,
                                 "✓ SIGNIFIKAN",
                                 "✗ Tidak Signifikan")
    )
  })
  
  output$lag_overlay <- renderPlotly({
    df <- lag_base_data()
    validate(need(nrow(df) > 4, "Data kosong."))
    
    # Pakai lag terbaik dari hasil korelasi
    peak_lag <- tryCatch({
      lag_corr_df() %>% arrange(desc(abs(r))) %>% slice(1) %>% pull(lag)
    }, error=function(e) 2)
    if (length(peak_lag)==0 || is.na(peak_lag)) peak_lag <- 2
    
    # Geser wabah maju peak_lag bulan ke depan (supaya bisa dioverlay dengan harga)
    df <- df %>%
      mutate(
        wabah_shifted = dplyr::lag(x_wabah, n=peak_lag),  # wabah t-lag
        z_harga       = as.numeric(scale(y_harga)),
        z_wabah       = as.numeric(scale(wabah_shifted))
      )
    
    validate(need(sum(!is.na(df$z_wabah)) > 3, "Tidak cukup data setelah shifting."))
    
    plot_ly() %>%
      add_trace(data=df, x=~periode, y=~z_harga,
                type="scatter", mode="lines+markers",
                name=paste0("Harga Hilir (", paste(input$lag_prov_hilir, collapse="+"), ") — t"),
                line=list(color="#1a3a5c", width=2.5),
                marker=list(color="#1a3a5c", size=5),
                hovertemplate="%{x}: z=%{y:.2f}<extra></extra>") %>%
      add_trace(data=df, x=~periode, y=~z_wabah,
                type="scatter", mode="lines+markers",
                name=paste0("Wabah Hulu (", paste(input$lag_prov_hulu, collapse="+"), ") — t-", peak_lag),
                line=list(color="#c0392b", width=2, dash="dash"),
                marker=list(color="#c0392b", size=5),
                hovertemplate="%{x}: z=%{y:.2f}<extra></extra>") %>%
      layout(
        xaxis=list(title="Periode", tickangle=-45, tickfont=list(size=8)),
        yaxis=list(title="Nilai Terstandarisasi (Z-score)"),
        hovermode="x unified",
        legend=list(orientation="h", y=-0.25),
        annotations=list(list(
          x=0.01, y=0.98, xref="paper", yref="paper",
          text=paste0("Wabah digeser maju ", peak_lag,
                      " bulan | r = ",
                      round(tryCatch(
                        lag_corr_df() %>% arrange(desc(abs(r))) %>% slice(1) %>% pull(r),
                        error=function(e) NA), 3)),
          showarrow=FALSE, font=list(size=10, color="#555"), xanchor="left"
        ))
      )
  })
  
  # ===========================================================
  # TAB 5: SUPPLY–DEMAND GAP
  # ===========================================================
  
  gap_df <- reactive({
    cube() %>%
      group_by(tahun,bulan,nama_komoditas) %>%
      summarise(sum_vol_mutasi=sum(sum_vol_mutasi,na.rm=TRUE),
                avg_permintaan=mean(avg_permintaan_bulanan,na.rm=TRUE),
                sum_karkas=sum(sum_realisasi_karkas,na.rm=TRUE),
                avg_konsumsi=mean(avg_konsumsi_bulanan,na.rm=TRUE),
                .groups="drop") %>%
      mutate(gap_ekor=sum_vol_mutasi-avg_permintaan,
             gap_kg=sum_karkas-avg_konsumsi,
             time_key=tahun*100+bulan)
  })
  
  output$gap_surplus_mo <- renderValueBox({
    n <- gap_df() %>% filter(gap_ekor>0) %>% nrow()
    valueBox(n,"Bulan-Komoditas Surplus",icon=icon("arrow-up"),color="green")
  })
  output$gap_deficit_mo <- renderValueBox({
    n <- gap_df() %>% filter(gap_ekor<0) %>% nrow()
    valueBox(n,"Bulan-Komoditas Defisit",icon=icon("arrow-down"),color="red")
  })
  output$gap_avg_logistik <- renderValueBox({
    v <- round(mean(gap_df()$gap_ekor,na.rm=TRUE),0)
    valueBox(format(v,big.mark="."),"Rata-rata Gap Logistik (ekor)",icon=icon("truck"),color="blue")
  })
  output$gap_avg_konsumsi <- renderValueBox({
    v <- round(mean(gap_df()$gap_kg,na.rm=TRUE),0)
    valueBox(format(v,big.mark="."),"Rata-rata Gap Konsumsi (kg)",icon=icon("utensils"),color="purple")
  })
  
  output$gap_supply_demand <- renderPlotly({
    df <- cube() %>%
      group_by(tahun, bulan, nama_komoditas) %>%
      summarise(
        sum_realisasi_karkas = sum(sum_realisasi_karkas, na.rm=TRUE),
        avg_konsumsi_bulanan = sum(avg_konsumsi_bulanan, na.rm=TRUE),
        .groups = "drop"
      ) %>%
      mutate(tanggal = paste0(tahun, "-", sprintf("%02d", bulan))) %>%
      filter(nama_komoditas == "Sapi")
    
    validate(need(nrow(df) > 0, "Data kosong."))
    
    plot_ly() %>%
      add_bars(
        data = df,
        x = ~tanggal,
        y = ~sum_realisasi_karkas,
        name = "Supply: Realisasi Karkas",
        marker = list(color = "#FF6B6B")
      ) %>%
      add_lines(
        data = df,
        x = ~tanggal,
        y = ~avg_konsumsi_bulanan,
        name = "Demand: Target Konsumsi",
        line = list(color = "darkred", width = 3, dash = "dash"),
        mode = "lines+markers"
      ) %>%
      layout(
        title = "SUPPLY VS DEMAND SAPI",
        xaxis = list(title = "Periode"),
        yaxis = list(title = "Volume (Kg)"),
        barmode = "group",
        hovermode = "x unified"
      )
  })
  output$gap_deficit_prov <- renderPlotly({
    df <- cube() %>%
      group_by(nama_provinsi,nama_komoditas) %>%
      summarise(gap=sum(sum_vol_mutasi,na.rm=TRUE)-sum(avg_permintaan_bulanan,na.rm=TRUE),
                .groups="drop") %>%
      filter(gap<0) %>%
      arrange(gap) %>% head(12) %>%
      mutate(nama_provinsi=factor(nama_provinsi,levels=rev(nama_provinsi)))
    
    if (nrow(df)==0) {
      return(plot_ly() %>% layout(title="Tidak ada provinsi defisit pada filter ini."))
    }
    plot_ly(df, x=~gap, y=~nama_provinsi, color=~nama_komoditas,
            type="bar", orientation="h",
            colors=c("#1a3a5c","#c0392b"),
            hovertemplate="%{y}: %{x:,.0f}<extra></extra>") %>%
      layout(xaxis=list(title="Gap (ekor, negatif=defisit)",tickformat=","),
             yaxis=list(title=""), barmode="group", margin=list(l=140))
  })
  
  output$gap_konsumsi <- renderPlotly({
    df <- gap_df() %>%
      group_by(nama_komoditas) %>%
      summarise(surplus=sum(gap_kg>0,na.rm=TRUE),
                defisit=sum(gap_kg<0,na.rm=TRUE),.groups="drop") %>%
      tidyr::pivot_longer(c(surplus,defisit),names_to="status",values_to="n")
    
    validate(need(nrow(df)>0,"Data kosong."))
    plot_ly(df, x=~nama_komoditas, y=~n, color=~status,
            type="bar", colors=c("defisit"="#c0392b","surplus"="#1e8449")) %>%
      layout(xaxis=list(title="Komoditas"),
             yaxis=list(title="Jumlah Bulan"), barmode="group")
  })
  
  # ===========================================================
  # TAB 6: PETA RISIKO SPASIAL
  # ===========================================================
  
  # Reactive: gunakan INDONESIA_SF dari rnaturalearth; fallback ke bubble centroid
  shp_obj <- reactive({
    if (!is.null(INDONESIA_SF) && nrow(INDONESIA_SF) > 0) {
      return(list(type = "rnaturalearth", data = INDONESIA_SF))
    }
    list(type = "bubble", data = NULL)
  })
  
  output$peta_status_banner <- renderUI({
    mode <- shp_obj()$type
    if (mode == "rnaturalearth") {
      tags$div(class="peta-info",
               icon("check-circle"),
               " Peta choropleth menggunakan data batas provinsi dari package ",
               tags$b("rnaturalearth"), " (tidak memerlukan file SHP atau koneksi internet)."
      )
    } else {
      tags$div(class="alert-banner alert-waspada",
               icon("map-marker-alt"),
               " rnaturalearth tidak tersedia. Menampilkan bubble map dari koordinat centroid provinsi. ",
               tags$b("Install package rnaturalearth & rnaturalearthdata untuk choropleth.")
      )
    }
  })
  
  peta_data <- reactive({
    df <- cube_raw()
    if (!is.null(input$peta_komoditas) && input$peta_komoditas != "Semua")
      df <- df %>% filter(nama_komoditas == input$peta_komoditas)
    thn <- as.integer(req(input$peta_tahun))
    df <- df %>%
      filter(tahun == thn) %>%
      group_by(nama_provinsi) %>%
      summarise(
        supply_risk_index = mean(supply_risk_index,na.rm=TRUE),
        avg_harga         = mean(avg_harga,na.rm=TRUE),
        sum_jumlah_sakit  = sum(sum_jumlah_sakit,na.rm=TRUE),
        sum_vol_mutasi    = sum(sum_vol_mutasi,na.rm=TRUE),
        populasi_ternak   = mean(populasi_ternak,na.rm=TRUE),
        .groups="drop"
      ) %>%
      mutate(zona=alert_status(supply_risk_index))
    df
  })
  
  output$peta_map <- renderLeaflet({
    obj    <- shp_obj()
    data   <- peta_data()
    metric <- input$peta_metric
    
    validate(need(nrow(data)>0,"Data kosong untuk tahun ini."))
    
    if (obj$type %in% c("shp","geojson","rnaturalearth")) {
      # --- Choropleth ---
      shp    <- obj$data
      merged <- join_peta(shp, data)
      
      pal_vals <- merged[[metric]]
      if (metric == "supply_risk_index") {
        pal <- colorNumeric(c("#1e8449","#f9e79f","#d35400","#c0392b"),
                            domain=c(0,1), na.color="#cccccc")
      } else {
        rng <- range(pal_vals, na.rm=TRUE)
        if (diff(rng)==0) rng <- c(rng[1]-1, rng[1]+1)
        pal <- colorNumeric(c("#d7eaf5","#1a3a5c"), domain=rng, na.color="#cccccc")
      }
      
      leaflet(merged) %>%
        addProviderTiles(providers$CartoDB.Positron) %>%
        addPolygons(
          fillColor  = ~pal(get(metric)),
          fillOpacity= 0.75,
          color      = "#ffffff",
          weight     = 1,
          highlightOptions=highlightOptions(
            weight=2.5,color="#0d1f35",fillOpacity=0.9,bringToFront=TRUE),
          popup=~paste0(
            "<b>",PROVINSI,"</b><br>",
            "Risk Index: <b>",round(supply_risk_index,4),"</b><br>",
            "Zona: <b>",zona,"</b><br>",
            "Harga: Rp ",format(round(avg_harga,0),big.mark="."),"<br>",
            "Jml Sakit: ",format(round(sum_jumlah_sakit,0),big.mark="."),"<br>",
            "Vol Mutasi: ",format(round(sum_vol_mutasi,0),big.mark=".")," ekor"
          )
        ) %>%
        addLegend("bottomright",pal=pal,values=pal_vals,
                  title=metric,opacity=0.8)
      
    } else {
      # --- Bubble fallback dari centroid ---
      df_bubble <- PROV_CENTROID %>%
        mutate(nama_provinsi=toupper(nama_provinsi)) %>%
        left_join(data, by="nama_provinsi") %>%
        filter(!is.na(supply_risk_index))
      
      pal_risk <- colorNumeric(c("#1e8449","#f9e79f","#d35400","#c0392b"),
                               domain=c(0,1), na.color="#cccccc")
      
      leaflet(df_bubble) %>%
        addProviderTiles(providers$CartoDB.Positron) %>%
        setView(lng=118, lat=-2, zoom=4) %>%
        addCircleMarkers(
          lng=~lon, lat=~lat,
          radius=~pmax(6, pmin(30, supply_risk_index*40)),
          fillColor=~pal_risk(supply_risk_index),
          fillOpacity=0.8,
          color="#0d1f35", weight=1,
          popup=~paste0(
            "<b>",nama_provinsi,"</b><br>",
            "Risk Index: <b>",round(supply_risk_index,4),"</b><br>",
            "Zona: <b>",zona,"</b><br>",
            "Harga: Rp ",format(round(avg_harga,0),big.mark="."),"<br>",
            "Jml Sakit: ",round(sum_jumlah_sakit,0)
          )
        ) %>%
        addLegend("bottomright",pal=pal_risk,values=~supply_risk_index,
                  title="Supply Risk Index",opacity=0.8)
    }
  })
  
  output$peta_bubble <- renderPlotly({
    df <- peta_data() %>%
      mutate(disease_density=sum_jumlah_sakit/(pmax(populasi_ternak,1)/1000))
    
    validate(need(nrow(df)>0,"Data kosong."))
    colors <- c("BAHAYA"="#c0392b","WASPADA"="#d68910","AMAN"="#1e8449")
    plot_ly(df, x=~populasi_ternak, y=~disease_density,
            size=~supply_risk_index, color=~zona,
            colors=colors, type="scatter", mode="markers",
            text=~nama_provinsi,
            marker=list(sizemode="area",opacity=0.75,sizeref=0.01),
            hovertemplate=paste0("<b>%{text}</b><br>",
                                 "Populasi: %{x:,.0f} ekor<br>",
                                 "Disease Density: %{y:.2f} kasus/1000 ekor<br>",
                                 "Risk: %{marker.size:.3f}<extra></extra>")) %>%
      layout(xaxis=list(title="Populasi Ternak (ekor)",tickformat=","),
             yaxis=list(title="Disease Density (kasus/1000 ekor)"),
             legend=list(title=list(text="Zona")))
  })
  
  # ===========================================================
  # TAB 7: DEPENDENSI SUPPLY
  # ===========================================================
  
  output$supply_prov_filter_ui <- renderUI({
    semua_prov <- sort(unique(cube_raw()$nama_provinsi))
    selectInput("supply_prov_filter", NULL,
                choices  = semua_prov,
                selected = semua_prov,
                multiple = TRUE,
                width    = "100%")
  })
  
  supply_conc <- reactive({
    df <- cube()
    # Filter provinsi jika ada pilihan
    if (!is.null(input$supply_prov_filter) && length(input$supply_prov_filter) > 0)
      df <- df %>% filter(nama_provinsi %in% input$supply_prov_filter)
    df %>%
      group_by(nama_provinsi) %>%
      summarise(sum_vol=sum(sum_vol_mutasi,na.rm=TRUE),
                pop=mean(populasi_ternak,na.rm=TRUE),
                risk=mean(supply_risk_index,na.rm=TRUE),.groups="drop") %>%
      arrange(desc(sum_vol)) %>%
      mutate(pct=sum_vol/sum(sum_vol)*100,
             cumsum_pct=cumsum(pct))
  })
  
  output$supply_pareto <- renderPlotly({
    df <- supply_conc() %>% head(15)
    validate(need(nrow(df)>0,"Data kosong."))
    fig <- plot_ly()
    fig <- fig %>%
      add_bars(data=df, x=~nama_provinsi, y=~sum_vol, name="Volume Supply",
               marker=list(color="#1a3a5c"),
               hovertemplate="%{x}: %{y:,.0f}<extra></extra>") %>%
      add_trace(data=df, x=~nama_provinsi, y=~cumsum_pct,
                type="scatter", mode="lines+markers", name="Kumulatif %", yaxis="y2",
                line=list(color="#c0392b",width=2.5),
                marker=list(color="#c0392b",size=7),
                hovertemplate="%{y:.1f}%<extra></extra>")
    fig %>% layout(
      xaxis=list(title="Provinsi",tickangle=-45),
      yaxis=list(title="Volume Mutasi (ekor)",tickformat=","),
      yaxis2=list(title="Kumulatif %",overlaying="y",side="right",range=c(0,100)),
      legend=list(x=0.1,y=1)
    )
  })
  
  output$supply_treemap <- renderPlotly({
    df <- supply_conc()
    validate(need(nrow(df)>0,"Data kosong."))
    plot_ly(df, type="treemap",
            labels=~nama_provinsi, values=~sum_vol,
            parents=rep("",nrow(df)),
            hovertemplate="%{label}: %{value:,.0f} (%{percentParent:.1%})<extra></extra>",
            marker=list(colorscale="Blues")) %>%
      layout(margin=list(t=0,b=0,l=0,r=0))
  })
  
  output$supply_vulner_table <- renderDT({
    df <- supply_conc() %>%
      filter(pct >= 10 & risk >= 0.3) %>%
      select(Provinsi=nama_provinsi,`Vol Supply`=sum_vol,
             `% Nasional`=pct,`Avg Risk`=risk) %>%
      mutate(`Vol Supply`=round(`Vol Supply`,0),
             `% Nasional`=round(`% Nasional`,2),
             `Avg Risk`=round(`Avg Risk`,4))
    
    if (nrow(df)==0) {
      return(datatable(
        data.frame(Info="Tidak ada provinsi rentan (supply ≥10% & risk ≥0.3) pada filter ini."),
        rownames=FALSE, options=list(dom="t")))
    }
    datatable(df, rownames=FALSE, options=list(dom="t")) %>%
      formatStyle("Avg Risk",
                  backgroundColor=styleInterval(c(0.3,0.6), c("#eafaf1","#fef5ec","#fdecea")))
  })
  
  # ===========================================================
  # TAB 8: DISPARITAS HARGA REGIONAL VS TEMPORAL
  # ===========================================================
  
  output$disp_strip <- renderPlotly({
    df <- cube() %>%
      filter(!is.na(avg_harga)) %>%
      mutate(periode=paste0(tahun,"/",sprintf("%02d",bulan)))
    validate(need(nrow(df)>0,"Data kosong."))
    
    plot_ly(df, x=~periode, y=~avg_harga, color=~nama_komoditas,
            type="box", colors=c("#1a3a5c","#c0392b"),
            boxpoints="outliers",
            hovertemplate="%{y:,.0f}<extra></extra>") %>%
      layout(xaxis=list(title="Periode",tickangle=-90,tickfont=list(size=8)),
             yaxis=list(title="Harga (Rp)",tickformat=","),
             boxmode="group",
             annotations=list(list(
               x=0.01, y=0.97, xref="paper", yref="paper",
               text="Sebaran vertikal = disparitas antar-provinsi",
               showarrow=FALSE, font=list(size=10,color="#777")
             )))
  })
  
  output$disp_cv_bar <- renderPlotly({
    df <- cube() %>%
      group_by(nama_provinsi, nama_komoditas) %>%
      summarise(
        mean_h = mean(avg_harga, na.rm=TRUE),
        sd_h   = sd(avg_harga, na.rm=TRUE),
        .groups="drop"
      ) %>%
      mutate(cv=sd_h/pmax(mean_h,1)*100) %>%
      arrange(desc(cv)) %>%
      filter(!is.na(cv))
    
    validate(need(nrow(df)>0,"Data kosong."))
    plot_ly(df, x=~cv, y=~reorder(nama_provinsi,cv), color=~nama_komoditas,
            type="bar", orientation="h",
            colors=c("#1a3a5c","#c0392b"),
            hovertemplate="%{y}: CV %{x:.1f}%<extra></extra>") %>%
      layout(xaxis=list(title="Koefisien Variasi Harga (%)"),
             yaxis=list(title=""),
             barmode="group",
             margin=list(l=140),
             annotations=list(list(
               x=0.99, y=0.01, xref="paper", yref="paper",
               text="CV tinggi = harga tidak stabil sepanjang waktu",
               showarrow=FALSE, xanchor="right", font=list(size=10,color="#777")
             )))
  })
  
  output$disp_heatmap <- renderPlotly({
    kom <- if (!is.null(input$sel_komoditas) && input$sel_komoditas!="Semua")
      input$sel_komoditas else "Sapi"
    
    df <- cube_raw() %>%
      filter(nama_komoditas == kom, !is.na(avg_harga)) %>%
      group_by(nama_provinsi, tahun, bulan) %>%
      summarise(avg_harga=mean(avg_harga,na.rm=TRUE),.groups="drop") %>%
      mutate(periode=paste0(tahun,"/",sprintf("%02d",bulan)))
    
    validate(need(nrow(df)>0,"Data kosong."))
    mat <- df %>%
      select(nama_provinsi,periode,avg_harga) %>%
      tidyr::pivot_wider(names_from=periode,values_from=avg_harga,values_fn=mean)
    
    prov_names <- mat$nama_provinsi
    mat_vals   <- as.matrix(mat[,-1])
    
    plot_ly(z=mat_vals, x=colnames(mat_vals), y=prov_names,
            type="heatmap",
            colorscale=list(c(0,"#d7eaf5"),c(0.5,"#5b9bd5"),c(1,"#1a3a5c")),
            hovertemplate="%{y}<br>%{x}: Rp %{z:,.0f}<extra></extra>") %>%
      layout(title=paste0("Heatmap Harga — Komoditas ",kom),
             xaxis=list(tickangle=-90,tickfont=list(size=8)),
             yaxis=list(tickfont=list(size=9)))
  })
  
  # ===========================================================
  # TAB 9: OLAP EXPLORER
  # ===========================================================
  
  output$olap_filter1 <- renderUI({
    switch(input$olap_op,
           "slice_kom"  = selectInput("o1","Komoditas",choices=c("Sapi","Ayam")),
           "slice_prov" = selectInput("o1","Provinsi", choices=sort(unique(cube_raw()$nama_provinsi))),
           "slice_thn"  = selectInput("o1","Tahun",    choices=sort(unique(cube_raw()$tahun),decreasing=TRUE)),
           "dice"       = selectInput("o1","Komoditas",choices=c("Sapi","Ayam")),
           "rollup_thn" = NULL,
           "rollup_prov"= NULL,
           "drilldown"  = selectInput("o1","Provinsi", choices=sort(unique(cube_raw()$nama_provinsi)))
    )
  })
  
  output$olap_filter2 <- renderUI({
    switch(input$olap_op,
           "dice"      = selectInput("o2","Provinsi",choices=sort(unique(cube_raw()$nama_provinsi))),
           "drilldown" = selectInput("o2","Tahun",   choices=sort(unique(cube_raw()$tahun),decreasing=TRUE)),
           NULL
    )
  })
  
  output$olap_filter3 <- renderUI({
    if (input$olap_op=="dice")
      selectInput("o3","Tahun",choices=sort(unique(cube_raw()$tahun),decreasing=TRUE))
    else NULL
  })
  
  olap_result_df <- reactive({
    df <- cube_raw()
    switch(input$olap_op,
           "slice_kom"  = df %>% filter(nama_komoditas==input$o1) %>%
             group_by(nama_provinsi,tahun,bulan) %>%
             summarise(risk=round(mean(supply_risk_index,na.rm=TRUE),4),
                       avg_harga=round(mean(avg_harga,na.rm=TRUE),0),.groups="drop"),
           "slice_prov" = df %>% filter(nama_provinsi==input$o1) %>%
             group_by(nama_komoditas,tahun,bulan) %>%
             summarise(risk=round(mean(supply_risk_index,na.rm=TRUE),4),
                       avg_harga=round(mean(avg_harga,na.rm=TRUE),0),.groups="drop"),
           "slice_thn"  = df %>% filter(tahun==as.integer(input$o1)) %>%
             group_by(nama_provinsi,nama_komoditas,bulan) %>%
             summarise(risk=round(mean(supply_risk_index,na.rm=TRUE),4),.groups="drop"),
           "dice"       = df %>% filter(nama_komoditas==input$o1,
                                        nama_provinsi==input$o2,
                                        tahun==as.integer(input$o3)) %>%
             select(bulan,nama_bulan,supply_risk_index,avg_harga,sum_jumlah_sakit),
           "rollup_thn" = df %>% group_by(tahun) %>%
             summarise(avg_risk=round(mean(supply_risk_index,na.rm=TRUE),4),
                       avg_harga=round(mean(avg_harga,na.rm=TRUE),0),
                       total_sakit=sum(sum_jumlah_sakit,na.rm=TRUE),.groups="drop"),
           "rollup_prov"= df %>% group_by(nama_provinsi,nama_komoditas) %>%
             summarise(avg_risk=round(mean(supply_risk_index,na.rm=TRUE),4),
                       avg_harga=round(mean(avg_harga,na.rm=TRUE),0),
                       total_sakit=sum(sum_jumlah_sakit,na.rm=TRUE),.groups="drop") %>%
             arrange(desc(avg_risk)),
           "drilldown"  = df %>% filter(nama_provinsi==input$o1,tahun==as.integer(input$o2)) %>%
             arrange(bulan,nama_komoditas) %>%
             select(bulan,nama_bulan,nama_komoditas,supply_risk_index,avg_harga,sum_jumlah_sakit),
           df
    )
  })
  
  output$olap_result <- renderDT({
    validate(need(nrow(olap_result_df())>0,"Tidak ada data untuk kombinasi filter ini."))
    datatable(olap_result_df(), rownames=FALSE,
              options=list(scrollX=TRUE,pageLength=12),
              class="stripe hover")
  })
  
  output$olap_chart <- renderPlotly({
    df  <- olap_result_df()
    req(nrow(df)>0)
    op  <- input$olap_op
    risk_col <- if ("risk" %in% names(df)) "risk" else
      if ("avg_risk" %in% names(df)) "avg_risk" else "supply_risk_index"
    
    if (op %in% c("rollup_thn","slice_thn")) {
      plot_ly(df, x=~get(names(df)[1]), y=~get(risk_col), type="bar",
              marker=list(color="#1a3a5c"),
              hovertemplate="%{x}: %{y:.4f}<extra></extra>") %>%
        layout(xaxis=list(title=""), yaxis=list(title="Risk Index"))
    } else if (op %in% c("drilldown","slice_prov","slice_kom")) {
      x_col   <- if ("bulan" %in% names(df)) "bulan" else names(df)[1]
      col_var <- if ("nama_komoditas" %in% names(df)) "nama_komoditas" else NULL
      if (!is.null(col_var)) {
        plot_ly(df, x=~get(x_col), y=~get(risk_col), color=~get(col_var),
                type="scatter", mode="lines+markers",
                colors=c("#1a3a5c","#c0392b")) %>%
          layout(xaxis=list(title="Bulan"), yaxis=list(title="Risk Index"))
      } else {
        plot_ly(df, x=~get(x_col), y=~get(risk_col),
                type="scatter", mode="lines+markers",
                line=list(color="#1a3a5c")) %>%
          layout(xaxis=list(title=""), yaxis=list(title="Risk Index"))
      }
    } else {
      x_nm <- names(df)[1]
      plot_ly(df, x=~get(x_nm), y=~get(risk_col), type="bar",
              marker=list(color="#1a3a5c")) %>%
        layout(xaxis=list(title="",tickangle=-45), yaxis=list(title="Risk Index"))
    }
  })
  
} # end server

# ============================================================
# RUN APP
# ============================================================

shinyApp(ui=ui, server=server)