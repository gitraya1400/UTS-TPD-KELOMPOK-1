# 🐄 LIVESTOCK INTELLIGENCE - R SHINY DASHBOARD

**Kelompok 1 TPD (3SI1) | POLSTAT STIS | 2025/2026**

Integrated OLAP-based analytics dashboard untuk livestock supply chain intelligence, terintegrasi dengan Data Warehouse PostgreSQL yang berisi data BPS, iSIKHNAS, dan PIHPS.

---

## 📋 Daftar Isi

1. [Overview](#overview)
2. [Fitur Utama](#fitur-utama)
3. [Setup & Installation](#setup--installation)
4. [Konfigurasi](#konfigurasi)
5. [Menjalankan Dashboard](#menjalankan-dashboard)
6. [Struktur Folder](#struktur-folder)
7. [OLAP Operations](#olap-operations)
8. [Data Sources](#data-sources)
9. [Troubleshooting](#troubleshooting)

---

## 📊 Overview

Dashboard ini merupakan implementasi **OLAP (Online Analytical Processing)** untuk analisis ketahanan pangan ternak di Indonesia. Mengintegrasikan 3 sumber data (BPS, iSIKHNAS, PIHPS) ke dalam **fact_supply_resilience** dengan 3 dimensi (prov, waktu, komoditas).

**Tujuan Utama:**
- Early Warning System untuk risiko pasokan
- Analisis korelasi harga-wabah penyakit
- Deteksi supply-demand gap
- Spatial risk mapping
- Analisis ketergantungan supply antar wilayah

---

## ✨ Fitur Utama

### 1. **Executive Summary**
- KPI boxes real-time (Critical provs, Warning provs, Avg Risk, Deficit regions)
- Current alert status terbaru dengan severity color coding
- National trend visualization (ROLL-UP: Annual)
- Risk zone distribution

### 2. **Early Warning System**
- Supply Risk Index = (Price Gap + Health Impact + Supply Strain) / 3
- Top 10 provinsi risiko tertinggi (ROLL-UP)
- Risk timeline untuk top 5 berisiko (DRILL-DOWN: Monthly)
- Risk component analysis
- Detailed monthly-level assessment table

### 3. **Price-Disease Correlation Analysis**
- Pearson correlation dengan p-value significance testing
- Dual-axis time series: Harga vs Jumlah Sakit
- Scatter plot dengan regression line
- Interpretasi otomatis korelasi

### 4. **Supply-Demand Gap Analysis**
- Level Logistik: Mutasi vs Permintaan (ekor)
- Level Konsumsi: Karkas vs Konsumsi (Kg)
- Gap timeline (DRILL-DOWN: Monthly)
- Top deficit provinces ranking
- Gap distribution by commodity

### 5. **Spatial Risk Map**
- **Interactive Choropleth Map** dengan Leaflet
- Spatial join: Shapefile ADMINISTRAS_PROVINSI.shp → Database by province name
- Risk zone classification (RED/ORANGE/GREEN)
- Bubble chart: Population vs Disease Density
- Hover tooltips dengan detail informasi

### 6. **Supply Dependency Analysis**
- Key suppliers identification (Pareto 80% rule)
- Pareto charts untuk sapi dan ayam
- Supply concentration analysis
- Vulnerability assessment untuk supplier kunci

### 7. **Data Explorer**
- Full OLAP cube browser dengan search & filter
- Export ke CSV, Excel, PDF
- Pagination dan sorting

### 8. **Documentation**
- OLAP concepts explanation
- Metrics definition glossary
- Filter logic documentation
- Data sources overview

---

## 🚀 Setup & Installation

### Prerequisites
- **R** (≥ 4.0)
- **PostgreSQL** (≥ 12) dengan Data Warehouse yang sudah jalan
- **RStudio** (recommended)
- **Git**

### Step 1: Clone Repository

```bash
cd /path/to/project
git clone <repo_url>
cd R_SHINY_DASHBOARD
```

### Step 2: Install R Packages

```bash
# Option A: Menggunakan install.packages() di R console
install.packages(readLines("REQUIREMENTS.txt"))

# Option B: Menggunakan script (automated)
Rscript install_dependencies.R
```

**Packages yang akan diinstall:**
- shiny, shinydashboard, shinyWidgets
- tidyverse (dplyr, ggplot2, etc.)
- plotly (interactive visualizations)
- sf, leaflet (spatial mapping)
- RPostgres, DBI, pool (database connection)
- DT (data tables)
- scales, lubridate, dan utilities lainnya

### Step 3: Configure Environment Variables

```bash
# Copy template environment file
cp .env.example .env

# Edit .env dengan text editor favorit Anda
nano .env  # atau gunakan editor lain
```

**Isi .env dengan konfigurasi database Anda:**

```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=datawarehouse_db
DB_USER=postgres
DB_PASSWORD=your_password
SHAPEFILE_PATH=data/ADMINISTRAS_PROVINSI.shp
```

### Step 4: Verifikasi Koneksi Database

```bash
# Di R console atau RStudio
source("config.R")
con <- create_db_connection()
dbListTables(con)  # Harus menampilkan fact_supply_resilience, dim_prov, dim_komoditas, dim_waktu
```

### Step 5: Tempatkan Shapefile

Pastikan file shapefile ada di folder `data/`:

```bash
# Struktur folder harus:
R_SHINY_DASHBOARD/
├── app.R
├── data/
│   └── ADMINISTRAS_PROVINSI.shp
│   └── ADMINISTRAS_PROVINSI.shx
│   └── ADMINISTRAS_PROVINSI.dbf
│   └── ADMINISTRAS_PROVINSI.prj  (opsional)
├── .env
└── ...
```

---

## ⚙️ Konfigurasi

### Database Connection

Edit `config.R` untuk mengubah parameter:

```r
DB_CONFIG <- list(
  host = "localhost",      # Database host
  port = 5432,             # PostgreSQL port
  dbname = "datawarehouse_db",
  user = "postgres",
  password = Sys.getenv("DB_PASSWORD")  # Baca dari .env
)
```

### Risk Thresholds

Ubah threshold risiko di `config.R`:

```r
RISK_THRESHOLDS <- list(
  critical = 0.7,    # Risk Index >= 0.7 → CRITICAL
  warning = 0.5,     # Risk Index >= 0.5 → WARNING
  caution = 0.3,     # Risk Index >= 0.3 → CAUTION
  safe = 0.0         # Risk Index < 0.3 → SAFE
)
```

### Color Palette

Customize warna dashboard di `config.R`:

```r
COLOR_PALETTE <- list(
  risk_critical = "#d62728",  # Red
  risk_warning = "#ff7f0e",   # Orange
  primary = "#0066cc",        # Blue
  ...
)
```

### Spatial Configuration

Update konfigurasi peta di `config.R`:

```r
SPATIAL_CONFIG <- list(
  shapefile_path = "data/ADMINISTRAS_PROVINSI.shp",
  center_lat = -0.789,   # Indonesia center
  center_lon = 113.921,
  zoom_level = 5
)
```

---

## 🎯 Menjalankan Dashboard

### Dari RStudio

```r
# Method 1: Run App button
# 1. Buka file "app.R"
# 2. Klik "Run App" button di RStudio

# Method 2: runApp()
shiny::runApp()  # Di working directory R_SHINY_DASHBOARD

# Method 3: Specify path
shiny::runApp("/path/to/R_SHINY_DASHBOARD")
```

### Dari Terminal

```bash
# Navigate ke direktori dashboard
cd R_SHINY_DASHBOARD

# Run dengan Rscript
Rscript -e "shiny::runApp()"

# Run dengan background process (Linux/Mac)
nohup Rscript -e "shiny::runApp()" > app.log 2>&1 &

# Run di specific port
Rscript -e "shiny::runApp(port = 3838)"
```

### Akses Dashboard

Setelah app running, akses di browser:

```
http://localhost:3838
```

---

## 📁 Struktur Folder

```
R_SHINY_DASHBOARD/
├── app.R                      # Main Shiny application entry point
├── config.R                   # Configuration, thresholds, utilities
├── server_reactive.R          # Server logic & reactive expressions
├── ui_components.R            # (Optional) Reusable UI components
├── .env.example               # Environment variables template
├── REQUIREMENTS.txt           # R packages list
├── data/
│   └── ADMINISTRAS_PROVINSI.shp    # Shapefile (pastikan ada)
│   └── ADMINISTRAS_PROVINSI.shx
│   └── ADMINISTRAS_PROVINSI.dbf
│   └── ADMINISTRAS_PROVINSI.prj
├── README.md                  # This file
├── DEPLOYMENT.md              # Server deployment guide
└── ...
```

---

## 🔄 OLAP Operations

Dashboard ini mengimplementasikan 4 operasi OLAP utama:

### 1. **SLICING**
Filter pada satu dimensi.

**Contoh:** 
```
Pilih hanya Provinsi "Jawa Timur"
→ Filter data by nama_provinsi = 'JAWA TIMUR'
```

**Di Dashboard:**
- Provinsi dropdown filter

### 2. **DICING**
Filter pada multiple dimensi.

**Contoh:**
```
Sapi + Jawa Timur + 2024 + Q1
→ Filter by komoditas='Sapi' AND nama_provinsi='JAWA TIMUR' 
   AND tahun=2024 AND kuartal='Q1'
```

**Di Dashboard:**
- Kombinasi: Provinsi + Komoditas + Year Range + Quarter

### 3. **ROLL-UP**
Agregasi data ke level lebih tinggi.

**Contoh:**
```
Dari: Detail Bulan (34 provinsi × 2 komoditas × 60 bulan)
Ke: Level Provinsi (agregasi by SUM/AVG across tahun-bulan)

SELECT nama_provinsi, 
       AVG(supply_risk_index),
       SUM(sum_jumlah_sakit)
FROM fact_supply_resilience
GROUP BY nama_provinsi
```

**Di Dashboard:**
- Top 10 Provinsi Risk → ROLL-UP by Province
- Current Alert Status → ROLL-UP by Latest Month
- Pareto Chart → ROLL-UP by Province & sort by supply

### 4. **DRILL-DOWN**
Disagregasi data ke level lebih detail.

**Contoh:**
```
Dari: Agregasi Nasional/Tahun
Ke: Detail Bulan per Provinsi per Komoditas

SELECT nama_provinsi, tahun, bulan, ...
FROM fact_supply_resilience
WHERE tahun = 2024
ORDER BY tahun, bulan
```

**Di Dashboard:**
- Risk Timeline → DRILL-DOWN from Year to Monthly
- Detailed Risk Table → DRILL-DOWN: Monthly granularity
- Supply-Demand Gap Timeline → DRILL-DOWN: Monthly detail

---

## 📊 Data Sources

### BPS (Badan Pusat Statistik)
- Population (jiwa)
- Livestock population (ekor): Sapi, Ayam
- Meat production (Kg)

### iSIKHNAS (Sistem Informasi Kesehatan Hewan)
- Livestock mutations (mutasi antar provinsi)
- Disease reports (laporan penyakit)
- Slaughter data (data pemotongan)

### PIHPS (Sistem Harga Pangan Strategis)
- Daily market prices
- Distribution levels (traditional, modern, wholesale)

### Shapefile
- ADMINISTRAS_PROVINSI.shp → Administrative boundaries Indonesia

---

## 🐛 Troubleshooting

### **Error: "object 'db_con' not found"**

```
Solusi:
1. Pastikan koneksi database berhasil
2. Verifikasi .env file
3. Restart session R
```

### **Error: "Cannot allocate vector of size X Gb"**

```
Solusi (untuk dataset besar):
1. Filter data lebih spesifik sebelum load
2. Gunakan window function di database query
3. Implementasi pagination di data explorer
```

### **Shapefile tidak muncul di map**

```
Troubleshooting:
1. Verifikasi path ke shapefile di config.R
2. Pastikan semua file shapefile ada (.shp, .shx, .dbf)
3. Check nama provinsi matching:
   - Shapefile: PROVINSI column
   - Database: nama_provinsi column
   - Harus match dengan case insensitive & trimmed
```

### **Database connection timeout**

```
Solusi:
1. Verifikasi PostgreSQL running
2. Test koneksi: psql -h localhost -U postgres -d datawarehouse_db
3. Increase timeout di config.R:
   timeout = 60  # second
4. Check firewall rules
```

### **Plotly charts tidak render**

```
Solusi:
1. Clear browser cache (Ctrl+Shift+Del)
2. Restart R session
3. Reinstall plotly: install.packages("plotly", force = TRUE)
```

### **Spatial map blank**

```
Troubleshooting:
1. Check browser console (F12 → Console)
2. Verify Leaflet tile server accessible (OpenStreetMap)
3. Test shapefile validity: sf::st_is_valid(shp_prov)
4. Check coordinate ranges
```

---

## 📈 Performance Optimization

### Database Query Optimization

Semua queries sudah menggunakan **Query Pushdown** (filtering di database level):

```r
# ✓ BAIK: Filter di database
query <- "
  SELECT * FROM fact_supply_resilience
  WHERE prov_key IN (1, 2, 3)
    AND tahun >= 2023
  LIMIT 10000
"

# ✗ BURUK: Filter di R (load semua data dulu)
data <- dbGetQuery(db_con, "SELECT * FROM fact_supply_resilience")
data_filtered <- data %>% filter(prov_key %in% c(1,2,3))
```

### Caching Strategy

Gunakan `reactive()` untuk cache hasil perhitungan:

```r
# ✓ Cached - hanya compute 1x sampai filtered_data berubah
avg_risk <- reactive({
  mean(filtered_data()$supply_risk_index, na.rm = TRUE)
})

# ✗ Not cached - recompute setiap kali diakses
output$kpi <- renderText({
  mean(filtered_data()$supply_risk_index, na.rm = TRUE)
})
```

### Expected Performance

Dengan dataset ~500K fact rows:
- Query execution: 50-300ms
- Page render: 1-3 seconds
- Interactive responsiveness: Smooth ✓

---

## 📚 References

- [Shiny Documentation](https://shiny.posit.co/)
- [Plotly R Guide](https://plotly.com/r/)
- [Leaflet R Documentation](https://rstudio.github.io/leaflet/)
- [sf Package (Spatial Features)](https://r-spatial.github.io/sf/)
- [DBI Package (Database Interface)](https://dbi.r-dbi.org/)

---

## 👥 Authors

**Kelompok 1 TPD (3SI1)**
- Anggita Cristin Meylani (222312982)
- Clarisse De Delgada M. Soares (222313033)
- M Rezky Raya Kilwouw (222313190)
- Nyimas Virna S. L. R (222313307)

**Institusi:** POLITEKNIK STATISTIKA STIS

**Tahun Ajaran:** 2025/2026

---

## 📄 License

Internal use only - POLSTAT STIS Project

---

**Last Updated:** 2026-05-05
