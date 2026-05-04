# 🚨 LIVESTOCK INTELLIGENCE - R SHINY DASHBOARD

## Deskripsi Sistem

**Livestock Intelligence** adalah dashboard interaktif berbasis R Shiny yang dirancang untuk **Sistem Peringatan Dini (Early Warning System)** ketahanan pangan nasional, khususnya komoditas daging sapi dan ayam. 

Dashboard ini mengintegrasikan data dari tiga sumber utama:
- **BPS**: Data demografi dan permintaan
- **iSIKHNAS**: Data kesehatan dan lalu lintas ternak
- **PIHPS**: Data harga pasar

Tujuan aplikasi adalah **mentransformasi manajemen ketahanan pangan dari metode reaktif menjadi kebijakan berbasis data (data-driven policy)**.

---

## 🏗️ Arsitektur Teknis

### Database Schema (Star Schema)
```
Fact Table: fact_supply_resilience
  ├── prov_key (FK → dim_prov)
  ├── waktu_key (FK → dim_waktu)
  ├── komoditas_key (FK → dim_komoditas)
  ├── Metrics: sum_jumlah_sakit, sum_jumlah_mati, sum_vol_mutasi, 
  │            sum_realisasi_karkas, avg_harga, supply_risk_index, ...
  │
Dimension Tables:
  ├── dim_prov (Spasial: nama_provinsi, prov_key)
  ├── dim_waktu (Temporal: tahun, bulan, kuartal, waktu_key)
  └── dim_komoditas (Produk: nama_komoditas, komoditas_key)
```

### OLAP Operations Implemented
- **SLICING**: Filter by province, commodity (radio buttons, dropdowns)
- **DICING**: Filter by year range, specific months (sliders, checkboxes)
- **ROLL-UP**: Aggregate from granular data to provincial level
- **DRILL-DOWN**: Explore from annual to monthly granularity
- **SPATIAL OLAP**: Join fact table with shapefile geometry for choropleth mapping

### Query Pushdown Strategy
```r
# ❌ WRONG: Loads entire fact table to R memory
data <- dbReadTable(con, "fact_supply_resilience")

# ✅ CORRECT: All filtering/aggregation happens in PostgreSQL
query <- tbl(con, "fact_supply_resilience") %>%
  filter(prov_key == X & komoditas_key == Y) %>%
  group_by(bulan) %>%
  summarise(avg_risk = mean(supply_risk_index)) %>%
  collect()  # ← collect() only at the end
```

---

## 📋 File Structure

```
R_SHINY_APP/
├── app.R                    # Main entry point
├── global.R                 # Library initialization, DB connection, utilities
├── ui.R                     # User interface layout (3 tabs)
├── server.R                 # Reactive logic, visualizations, OLAP operations
├── .env.example             # Environment variables template
├── requirements.txt         # R package dependencies
└── README.md               # This file

data/
└── ADMINISTRAS_PROVINSI.shp # Shapefile for spatial join (must be in this location)
```

---

## 🚀 Installation & Setup

### Prerequisites
- R >= 4.0
- PostgreSQL >= 12
- RStudio (recommended)

### Step 1: Install R Dependencies

```bash
# Option A: Using Rscript
Rscript install_packages.R

# Option B: Manually in R console
install.packages(c(
  "shiny", "shinydashboard", "shinyWidgets", "shinyalert",
  "DBI", "RPostgres", "dplyr", "dbplyr", "tidyr",
  "sf", "leaflet", "leaflet.extras",
  "plotly", "ggplot2", "scales", "treemapify",
  "lubridate", "zoo", "corrplot", "DT"
))
```

### Step 2: Configure Environment Variables

```bash
# Copy template and edit with your credentials
cp .env.example .env

# Edit .env with your PostgreSQL connection details
# DB_HOST=your.postgres.server
# DB_NAME=datawarehouse_db
# DB_USER=your_username
# DB_PASSWORD=your_password
```

### Step 3: Place Shapefile Data

```bash
# Ensure ADMINISTRAS_PROVINSI.shp is in a 'data' folder
mkdir -p data
# Copy ADMINISTRAS_PROVINSI.shp and related files to data/
cp ADMINISTRAS_PROVINSI.shp* data/
```

### Step 4: Launch Dashboard

```bash
# From R console or RStudio
setwd("path/to/R_SHINY_APP")
shiny::runApp()

# Or from terminal
Rscript -e "shiny::runApp()"
```

The app will be available at `http://localhost:3838`

---

## 📊 Dashboard Features

### TAB 1: Executive Summary (The Alarm) - Early Warning System

**Indikator Utama:**
- **Supply Risk Index (0-1 scale)**: 
  - Kombinasi dari Price Gap, Health Impact, dan Supply Strain
  - Sebelum averaging, semua komponen di-scale MIN-MAX ke range [0, 1]
  - Kategori: 
    - 0.0-0.33: 🟢 Aman
    - 0.33-0.67: 🟡 Peringatan
    - 0.67-1.0: 🔴 Bahaya

- **National Average Price**: Harga rata-rata komoditas di pasar
- **Total Disease Reports**: Jumlah laporan penyakit ternak
- **Supply Volume**: Total volume mutasi/pengiriman ternak

**Visualisasi:**
- Top 5 Provinces Bar Chart (sorted by risk index)
- **Choropleth Map (Spatial OLAP)**: 
  - Warna peta menunjukkan risk level per provinsi
  - Hover tooltip: Nama provinsi, risk index, jumlah sakit
  - Join key: `nama_provinsi` (standardized uppercase)

**Alert Otomatis:**
- Jika provinsi menyuplai > 60% dan risk index > 0.67, sistem menampilkan peringatan KRITIS

---

### TAB 2: Analisis Sektor Riil

**Supply vs Demand Gap Analysis:**
- **Level Logistik** (Ekor): sum_vol_mutasi vs avg_permintaan_bulanan
- **Level Konsumsi** (Kg): sum_realisasi_karkas vs avg_konsumsi_bulanan
- Menghitung gap (surplus/deficit)
- Positive gap = Surplus (aman)
- Negative gap = Deficit (warning)

**Supply Dependency Analysis:**
- Treemap visualization menunjukkan % kontribusi setiap provinsi
- Identifikasi provinsi "kunci" yang >60% supply nasional
- Tabel detail ranking supply contribution

**Alert Triggers:**
- Jika satu provinsi supply >60% DAN high risk → ALERT

---

### TAB 3: Investigasi & Korelasi

**Time Series Analysis (Dual-Axis):**
- **Left Axis**: avg_harga (IDR/kg)
- **Right Axis**: sum_jumlah_sakit + sum_jumlah_mati (ekor)
- Membantu visualisasi temporal relationship

**Correlation Coefficient (Pearson):**
- r > 0.7: Korelasi KUAT POSITIF
  - Interpretasi: Harga tinggi saat penyakit banyak → Supply failure
- r 0.3-0.7: Korelasi SEDANG
  - Interpretasi: Beberapa faktor lain juga berpengaruh
- r -0.3 to 0.3: Korelasi LEMAH/TIDAK ADA
  - Interpretasi: Harga naik karena faktor lain (musiman, spekulasi)
- r < -0.3: Korelasi NEGATIF
  - Interpretasi: Sistem resilient terhadap shock penyakit

**Visualisasi:**
- Dual-axis line chart (price vs disease over time)
- Scatter plot: Harga vs Jumlah Sakit
- Correlation matrix: Semua metrik kunci

---

## 🎛️ Filter Controls (OLAP Slicing & Dicing)

### SLICING
- **Provinsi**: "Nasional" (agregasi nasional) atau pilih provinsi tertentu
- **Komoditas**: Sapi atau Ayam (analisis terpisah per jenis)

### DICING
- **Tahun Range**: Slider untuk memilih rentang tahun (2020-2025)
- **Bulan**: Checkbox untuk memilih bulan spesifik (1-12)

**Filter Button**: "Apply Filters" untuk menjalankan query dengan kombinasi filter

---

## 🔧 Technical Implementation Details

### Database Connection (global.R)

```r
con <- dbConnect(
  RPostgres::Postgres(),
  host = Sys.getenv("DB_HOST"),
  port = Sys.getenv("DB_PORT"),
  dbname = Sys.getenv("DB_NAME"),
  user = Sys.getenv("DB_USER"),
  password = Sys.getenv("DB_PASSWORD")
)
```

### Spatial Data Loading

```r
# Read shapefile using sf package
spatial_data <- st_read("data/ADMINISTRAS_PROVINSI.shp")

# Spatial join dengan supply risk data
spatial_joined <- spatial_data %>%
  left_join(
    risk_data,
    by = "nama_provinsi"  # Join key: standardized province name
  )

# Render dengan leaflet choropleth
leaflet(spatial_joined) %>%
  addPolygons(
    fillColor = ~leaflet_risk_palette(risk_index),
    label = labels
  )
```

### Reactive Expressions (server.R)

```r
# Core reactive data - triggered by filter changes
filtered_data <- reactive({
  # Query dengan Query Pushdown
  data <- query_supply_resilience(
    prov = input$filter_provinsi,
    komoditas = input$filter_komoditas,
    year_range = input$filter_tahun,
    months = as.numeric(input$filter_bulan)
  )
  return(data)
})

# All outputs depend on filtered_data
output$chart <- renderPlotly({
  data <- filtered_data()  # Automatically reactively updated
  # ... create visualization
})
```

### Correlation Calculation

```r
# Calculate Pearson correlation
corr_val <- cor(
  data$avg_price,
  data$total_sick,
  use = "complete.obs",
  method = "pearson"
)

# Interpret result
if (corr_val > 0.7) {
  interpretation <- "KUAT POSITIF: Harga naik saat penyakit banyak"
} else if (corr_val > 0.3) {
  interpretation <- "SEDANG: Beberapa pengaruh penyakit pada harga"
} else {
  interpretation <- "LEMAH: Faktor lain lebih dominan"
}
```

---

## 📈 Key Metrics Explanation

### Supply Risk Index Formula

```
supply_risk_index = (price_gap + health_impact + supply_strain) / 3

Dimana (sebelum averaging, setiap komponen di-MIN-MAX SCALE ke [0,1]):

1. price_gap = (avg_harga - harga_baseline) / harga_baseline
   - Mengukur deviasi harga dari baseline pemerintah
   
2. health_impact = (sum_jumlah_sakit + sum_jumlah_mati) / populasi_ternak
   - Mengukur proporsi hewan yang sakit/mati terhadap populasi
   
3. supply_strain = sum_vol_mutasi / avg_permintaan_bulanan
   - Mengukur beban pengiriman terhadap kebutuhan bulanan
```

### Gap Analysis

```
gap_ekor = sum_vol_mutasi - avg_permintaan_bulanan
gap_kg = sum_realisasi_karkas - avg_konsumsi_bulanan

Positif = Surplus (overcapacity)
Negatif = Deficit (undercapacity/alarm)
```

### Dependency Concentration

```
percentage_national = (prov_supply / total_national_supply) × 100

> 60% = KRITIS (overconcentration)
40-60% = TINGGI (concentrated)
20-40% = SEDANG
< 20% = RENDAH (diversified)
```

---

## 🚨 Alert & Notification System

### Automatic Alerts Triggered:

1. **High Supply Dependency + High Risk**
   ```
   Trigger: supply% > 60% AND risk_index > 0.67
   Message: "BAHAYA: Ketergantungan tinggi pada provinsi berisiko!"
   Action: Notifikasi di Executive Summary tab
   ```

2. **Critical Dependency**
   ```
   Trigger: Any province with supply% > 60%
   Message: List semua provinsi kritis + rekomendasi diversifikasi
   Action: Notifikasi di Tab 2
   ```

---

## 📊 Example Queries Generated by Dashboard

### SLICING: Filter by Sapi di Jawa Timur

```sql
SELECT 
  p.nama_provinsi,
  AVG(f.supply_risk_index) AS avg_risk
FROM fact_supply_resilience f
JOIN dim_prov p ON f.prov_key = p.prov_key
JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
WHERE p.nama_provinsi = 'Jawa Timur'
  AND k.nama_komoditas = 'Sapi'
GROUP BY p.nama_provinsi
```

### DICING: Filter by Tahun 2024-2025, Bulan 1-6

```sql
SELECT 
  tahun, bulan,
  SUM(f.sum_vol_mutasi) AS total_supply,
  AVG(f.avg_harga) AS avg_price
FROM fact_supply_resilience f
JOIN dim_waktu w ON f.waktu_key = w.waktu_key
WHERE w.tahun IN (2024, 2025)
  AND w.bulan IN (1, 2, 3, 4, 5, 6)
GROUP BY tahun, bulan
ORDER BY tahun, bulan
```

### ROLL-UP: Aggregate to National Level

```sql
SELECT 
  AVG(f.supply_risk_index) AS national_risk,
  SUM(f.sum_jumlah_sakit) AS total_sick
FROM fact_supply_resilience f
JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
WHERE k.nama_komoditas = 'Sapi'
```

---

## 🐛 Troubleshooting

### Database Connection Failed
```
Error: "Database connection failed"
Solution: 
  1. Check DB_HOST, DB_PORT, DB_USER, DB_PASSWORD in .env
  2. Verify PostgreSQL service is running
  3. Ensure datawarehouse_db exists
  4. Test connection: psql -h DB_HOST -U DB_USER -d datawarehouse_db
```

### Shapefile Not Found
```
Error: "Shapefile not found: data/ADMINISTRAS_PROVINSI.shp"
Solution:
  1. Ensure file exists in R_SHINY_APP/data/ directory
  2. Check all supporting files present: .shx, .dbf, .prj, etc.
  3. Verify file permissions
  4. Choropleth map will be disabled if shapefile missing (non-fatal)
```

### No Data Displayed
```
Possible causes:
  1. Filters too restrictive (no matching data)
  2. Province/commodity names not matching database
  3. Date range outside available data range
  4. NULL values in critical columns
  
Debug: Check RStudio console for SQL error messages
```

### Slow Performance
```
Solution (in order of priority):
  1. Ensure database indexes are created:
     CREATE INDEX idx_fact_risk ON fact_supply_resilience(supply_risk_index);
  2. Reduce date range in filters
  3. Use specific provinces instead of "Nasional"
  4. Check database server resources
  5. Consider materializing common aggregations as views
```

---

## 📚 Further Development

### Recommended Enhancements:

1. **Real-time Data Integration**
   - Add Shiny refresh interval to query latest data
   - Implement notification push when risk > threshold

2. **Forecast Module**
   - Add time series forecasting (ARIMA, Prophet)
   - Predict risk index 1-3 months ahead

3. **Drill-down Analysis**
   - From national → provincial → district level
   - Link to individual health facility reports

4. **Export & Reporting**
   - Automated PDF report generation
   - Email notifications to stakeholders

5. **Mobile Dashboard**
   - Responsive design for mobile/tablet
   - Simplified KPI view for executives

6. **Machine Learning**
   - Anomaly detection for price spikes
   - Clustering of high-risk provinces

---

## 📞 Support & Contact

For issues or questions:
1. Check console output in RStudio for error messages
2. Verify database connection and data availability
3. Review log files for SQL query details
4. Contact data engineering team for database issues

---

## 📄 License

Internal Use Only - Livestock Intelligence Dashboard
Part of UTS-TPD-KELOMPOK-1 Project
Politeknik Statistika STIS

---

**Version**: 1.0  
**Last Updated**: 2026-05-04  
**Developed by**: v0 AI Assistant
