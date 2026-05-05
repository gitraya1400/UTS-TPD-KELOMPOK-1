# 🐄 Livestock Intelligence
### Analisis Populasi, Mutasi, dan Harga Daging Ternak Indonesia

**UTS Teknologi Perekayasaan Data — Kelompok 1 (3SI1) · Politeknik Statistika STIS · 2026**

---

## 📌 Deskripsi Proyek

**Livestock Intelligence** adalah sistem data warehouse berbasis OLAP yang dirancang untuk memantau dan menganalisis kondisi peternakan di Indonesia secara spasial dan temporal. Proyek ini mengintegrasikan empat sumber data berbeda (BPS, iSIKHNAS, PIPHPS, dan Shapefile) melalui pipeline ETL tiga fase, kemudian memvisualisasikannya dalam dashboard interaktif R Shiny.

Sistem ini mampu menghasilkan **Supply Risk Index** per provinsi, per komoditas (Sapi & Ayam), per bulan — mencakup tahun 2020 hingga 2025.

---

## 👥 Anggota Kelompok

| Nama | NIM |
|------|-----|
| *Anggita Cristin Meylani* | *222312982* |
| *Clarisse De Delgada M. Soares* | *222313033* |
| *M Rezky Raya Kilwouw* | *222313190* |
| *Nyimas Virna S. L. R* | *222313307* |


---

## 🗂️ Struktur Repositori

```
UTS-TPD-KELOMPOK-1/
│
├── CODE/
│   ├── EXTRACT/
│   │   ├── ETL_Extract_Kelompok1.ipynb     ← Notebook fase Extract
│   │   └── ETL_Extract_Kelompok1.py        ← Script Python fase Extract
│   ├── TRANSFORM/
│   │   ├── ETL_Transform_Kelompok1.ipynb   ← Notebook fase Transform (PySpark)
│   │   └── ETL_Transform_Kelompok1.py      ← Script Python fase Transform
│   ├── LOAD/
│   │   ├── ETL_Load_Kelompok1.ipynb        ← Notebook fase Load
│   │   └── ETL_Load_Kelompok1.py           ← Script Python fase Load
│   └── convert_notebooks.py               ← Konversi .ipynb → .py
│
├── DATA/
│   ├── BPS/                               ← Data scraping BPS SIMDASI + dummy
│   ├── ISHIKNAS/                          ← Data penyakit & mutasi ternak (MySQL dump + CSV)
│   ├── PIPHPS/                            ← Data harga daging realisasi karkas (Excel)
│   ├── STAGING/                           ← SQL dump staging_db
│   ├── DWH/                               ← SQL dump datawarehouse_db
│   ── TRANSFORM_OUTPUT/                  ← Hasil transform dalam format Parquet
│
├── OLAP/
│   └── olap olap.ipynb                    ← Eksplorasi OLAP awal
│
├── PLANS/
│   └── UTS_K203410-Teknologi Perekayasaan Data.pdf
│
├── livestock_dashboard/
│   ├── app.R                              ← Aplikasi R Shiny (utama)
│   ├── export_to_csv.R                    ← Export data DWH ke CSV
│   ├── README.md                          ← Panduan setup dashboard
│   └── data/                             ← Data lokal CSV untuk dashboard
│
├── materi dasar/                          ← Materi referensi TPD
├── postgresql-42.7.11.jar                 ← JDBC driver PostgreSQL
└── README.md
```

---

## 🏗️ Arsitektur Sistem

```
┌─────────────────────────────────────────────────────────┐
│                    SUMBER DATA                           │
│  BPS SIMDASI (API)  │  iSIKHNAS (MySQL)  │  PIPHPS (Excel) │
└────────────┬────────────────┬────────────────┬───────────┘
             │                │                │
             ▼                ▼                ▼
┌─────────────────────────────────────────────────────────┐
│           FASE 1 — EXTRACT (Python + SQLAlchemy)         │
│            → staging_db (PostgreSQL) · data as-is        │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│           FASE 2 — TRANSFORM (PySpark)                   │
│  Cleaning · Unpivot · Standardisasi · Imputasi           │
│  Bangun Dimensi · Hitung supply_risk_index               │
│            → Output: Parquet files                       │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│           FASE 3 — LOAD (PySpark JDBC)                   │
│         → datawarehouse_db (PostgreSQL)                  │
│   dim_prov · dim_komoditas · dim_waktu                   │
│        fact_supply_resilience                            │
└────────────────────────────┬────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────┐
│         R SHINY DASHBOARD — Livestock Intelligence       │
│   7 Tab OLAP · Peta Spasial Leaflet · Filter Global      │
└─────────────────────────────────────────────────────────┘
```

---

## 🗄️ Skema Data Warehouse

### Tabel Dimensi

| Tabel | Kolom Utama | Keterangan |
|-------|-------------|-----------|
| `dim_prov` | `prov_key`, `id_prov`, `nama_provinsi` | 34 provinsi Indonesia |
| `dim_komoditas` | `komoditas_key`, `id_komoditas`, `nama_komoditas` | Sapi, Ayam |
| `dim_waktu` | `waktu_key`, `tahun`, `bulan`, `kuartal`, `nama_bulan` | 2020–2025 |

### Tabel Fakta

**`fact_supply_resilience`** — tabel utama analisis

| Kolom | Tipe | Keterangan |
|-------|------|-----------|
| `fact_id` | integer | Primary key |
| `prov_key` | integer | FK → dim_prov |
| `waktu_key` | integer | FK → dim_waktu |
| `komoditas_key` | integer | FK → dim_komoditas |
| `jumlah_penduduk` | bigint | Populasi manusia |
| `sum_jumlah_sakit` | double | Jumlah ternak sakit |
| `sum_jumlah_mati` | double | Jumlah ternak mati |
| `sum_vol_mutasi` | double | Volume mutasi ternak |
| `sum_realisasi_karkas` | double | Realisasi karkas (ton) |
| `avg_harga` | double | Rata-rata harga daging |
| `populasi_ternak` | double | Total populasi ternak |
| `avg_konsumsi_bulanan` | double | Konsumsi rata-rata bulanan |
| `avg_pemotongan_bulanan` | double | Pemotongan rata-rata bulanan |
| `growth_populasi` | double | Pertumbuhan populasi (%) |
| `supply_risk_index` | double | **Indeks risiko pasokan** |

---

## 📊 Fitur Dashboard

| Tab | Operasi OLAP | Konten |
|-----|-------------|--------|
| **Beranda** | Roll-up | KPI card, distribusi zona risiko, tren nasional, alert table |
| **Early Warning System** | Roll-up + Slice | Top 10 risiko, timeline, heatmap provinsi × bulan |
| **Harga vs Wabah** | Dice + Correlation | Pearson r, dual-axis harga+wabah, scatter, boxplot kuartal |
| **Supply-Demand Gap** | Roll-up + Drill-down | Gap logistik & konsumsi, deficit per provinsi |
| **Peta Risiko Spasial** | Slice | Choropleth Leaflet, bubble chart populasi vs disease density |
| **Dependensi Supply** | Roll-up | Pareto chart, treemap, tabel provinsi kritis |
| **OLAP Explorer** | Slice/Dice/Roll-up/Drill-down | Filter interaktif penuh, tabel & chart dinamis |

**Filter Global (sidebar):** Komoditas · Tahun · Provinsi

---

## ⚙️ Cara Menjalankan

### Prasyarat

- Python 3.10+
- Java 11+ (untuk PySpark)
- Apache Spark 3.x
- PostgreSQL 14+
- MySQL 8+ (untuk iSIKHNAS)
- R 4.x + RStudio
- Hadoop (Windows: `winutils.exe`)

### 1. Install Dependensi Python

```bash
pip install pandas numpy sqlalchemy psycopg2-binary pymysql pyspark tqdm openpyxl
```

### 2. Siapkan Database

```sql
-- Di PostgreSQL
CREATE DATABASE staging_db;
CREATE DATABASE datawarehouse_db;

-- Di MySQL
CREATE DATABASE isikhnas_db;
```

Restore dump dari folder `DATA/STAGING/` dan `DATA/ISHIKNAS/` sesuai kebutuhan.

### 3. Konfigurasi Koneksi

Edit bagian konfigurasi di setiap script ETL:

```python
# Di ETL_Extract_Kelompok1.py
PG_USER = 'postgres'
PG_PASS = 'password'
PG_HOST = 'localhost'
PG_PORT = '5432'

MYSQL_USER = 'root'
MYSQL_PASS = ''
```

### 4. Jalankan Pipeline ETL

```bash
# Fase 1 — Extract
python CODE/EXTRACT/ETL_Extract_Kelompok1.py

# Fase 2 — Transform
python CODE/TRANSFORM/ETL_Transform_Kelompok1.py

# Fase 3 — Load
python CODE/LOAD/ETL_Load_Kelompok1.py
```

Atau gunakan Jupyter Notebook (`.ipynb`) untuk menjalankan per cell secara interaktif.

### 5. Jalankan Dashboard R Shiny

```r
# Install packages (otomatis atau manual)
install.packages(c(
  "shiny", "shinydashboard", "DBI", "RPostgres",
  "dplyr", "tidyr", "ggplot2", "plotly",
  "leaflet", "sf", "scales", "DT",
  "shinycssloaders", "fresh", "htmltools",
  "lubridate", "RColorBrewer"
))

# Edit DB_CONFIG di app.R, lalu:
setwd("livestock_dashboard/")
shiny::runApp("app.R")
```

> **Linux:** Mungkin perlu install GDAL terlebih dahulu:
> ```bash
> sudo apt-get install libgdal-dev libgeos-dev libproj-dev
> ```

---

## 📦 Sumber Data

| Sumber | URL / Lokasi | Keterangan |
|--------|-------------|-----------|
| BPS SIMDASI | [webapi.bps.go.id](https://webapi.bps.go.id) | API key wajib didaftarkan |
| iSIKHNAS | Dump lokal (`DATA/ISHIKNAS/`) | Data simulasi penyakit ternak |
| PIPHPS | `DATA/PIPHPS/final_data_lengkap.xlsx` | Harga daging provinsi |

---

## 🛠️ Tech Stack

![Python](https://img.shields.io/badge/Python-3.10-blue?logo=python)
![PySpark](https://img.shields.io/badge/PySpark-3.x-orange?logo=apachespark)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14+-336791?logo=postgresql)
![R](https://img.shields.io/badge/R-Shiny-276DC3?logo=r)

- **Bahasa:** Python 3.10, R 4.x
- **Big Data:** Apache PySpark (ETL Transform & Load)
- **Database:** PostgreSQL (Staging + DWH), MySQL (iSIKHNAS)
- **Dashboard:** R Shiny + shinydashboard + Leaflet + Plotly
- **Spasial:** sf, Leaflet (R)
- **Format antara:** Apache Parquet

---

## 📝 Catatan

- Data BPS sebagian menggunakan **dummy data** karena keterbatasan akses API untuk beberapa variabel (misal: produksi daging sapi).
- Variabel `supply_risk_index` dihitung pada fase Transform berdasarkan kombinasi populasi, penyakit, mutasi, harga, dan konsumsi.
- Nama provinsi di sf, leaflet dan DWH telah mapping (case-insensitive, trim) untuk memastikan join spasial berhasil.
- JDBC driver PostgreSQL (`postgresql-42.7.11.jar`) sudah disertakan di root repositori.

---

## 📄 Lisensi

Proyek ini dibuat untuk keperluan akademis UTS mata kuliah **Teknologi Perekayasaan Data** — Politeknik Statistika STIS.