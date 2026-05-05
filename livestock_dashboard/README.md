# Livestock Intelligence Dashboard — R Shiny
## Kelompok 1 (3SI1) · STIS · TPD 2026

---

## Struktur Folder

```
livestock_dashboard/
├── app.R                        ← File utama Shiny
├── Administrasi_provinsi.shp    ← ⚠️ WAJIB: letakkan di sini
├── Administrasi_provinsi.dbf    ← file pendamping shapefile
├── Administrasi_provinsi.shx    ← file pendamping shapefile
├── Administrasi_provinsi.prj    ← file pendamping shapefile (jika ada)
└── README.md
```

---

## Langkah Setup

### 1. Pastikan PostgreSQL DWH berjalan
Database: `datawarehouse_db`  
Tabel yang dibutuhkan: `fact_supply_resilience`, `dim_prov`, `dim_waktu`, `dim_komoditas`

### 2. Edit konfigurasi DB di `app.R`
```r
DB_CONFIG <- list(
  host     = "localhost",
  port     = 5432,
  dbname   = "datawarehouse_db",
  user     = "postgres",
  password = "ISI_PASSWORD_KALIAN"   # ← ganti ini
)
```

### 3. Letakkan file Shapefile
Download dari Google Drive yang sudah dibagikan, lalu letakkan semua file `.shp`, `.dbf`, `.shx`, `.prj`
di folder yang sama dengan `app.R`.

Path di `app.R`:
```r
SHP_PATH <- "Administrasi_provinsi.shp"
```

### 4. Install R packages (otomatis saat pertama jalan)
Atau install manual:
```r
install.packages(c(
  "shiny", "shinydashboard", "DBI", "RPostgres",
  "dplyr", "tidyr", "ggplot2", "plotly",
  "leaflet", "sf", "scales", "DT",
  "shinycssloaders", "fresh", "htmltools",
  "lubridate", "RColorBrewer"
))
```

> **Catatan sf**: Mungkin perlu `libgdal-dev` di Linux:
> ```bash
> sudo apt-get install libgdal-dev libgeos-dev libproj-dev
> ```

### 5. Jalankan
```r
setwd("path/ke/livestock_dashboard")
shiny::runApp("app.R")
```
Atau buka `app.R` di RStudio → klik **Run App**.

---

## Fitur Dashboard

| Tab | OLAP Operation | Isi |
|-----|---------------|-----|
| Beranda | Roll-up | KPI card, distribusi zona, tren risk nasional, alert table |
| Early Warning System | Roll-up + Slice | Top 10 risiko, timeline, heatmap provinsi×bulan |
| Harga vs Wabah | Dice + Correlation | Pearson r, dual-axis harga+wabah, scatter, boxplot kuartal |
| Supply-Demand Gap | Roll-up + Drill-down | Gap logistik & konsumsi, timeline, deficit per provinsi |
| Peta Risiko Spasial | Slice | Choropleth leaflet, bubble chart populasi vs disease density |
| Dependensi Supply | Roll-up | Pareto chart, treemap, tabel provinsi kritis |
| OLAP Explorer | Slice/Dice/Roll-up/Drill-down | Interaktif: pilih operasi, filter, lihat tabel & chart |

### Filter Global (sidebar)
- **Komoditas**: Semua / Sapi / Ayam
- **Tahun**: Semua / 2020–2025
- **Provinsi**: Semua / per provinsi

---

## Catatan Peta Spasial
Dashboard akan otomatis melakukan join antara shapefile dan data DWH berdasarkan nama provinsi (case-insensitive, trimmed).  
Jika ada nama yang tidak cocok, kolom akan tampil kosong (grey) di peta.  
Normalkan nama di shapefile jika perlu agar cocok dengan `dim_prov.nama_provinsi`.

---

## Matching Nama Provinsi (Shapefile → DWH)
| Di dim_prov | Kemungkinan di SHP |
|------------|-------------------|
| Aceh | ACEH |
| DI Yogyakarta | DI. YOGYAKARTA / D.I. YOGYAKARTA |
| DKI Jakarta | DKI. JAKARTA |

Jika tidak cocok, tambahkan baris di app.R:
```r
# Di dalam server, setelah shp <- st_read(...)
shp$PROVINSI_norm <- shp$PROVINSI_norm %>%
  gsub("DI\\. YOGYAKARTA", "DI YOGYAKARTA", .) %>%
  gsub("DKI\\. JAKARTA", "DKI JAKARTA", .)
```
