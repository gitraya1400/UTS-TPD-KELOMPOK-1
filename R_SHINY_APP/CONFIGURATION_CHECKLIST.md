# CONFIGURATION CHECKLIST
## Panduan Lengkap Konfigurasi Livestock Intelligence Dashboard

> **Status**: Ikuti checklist ini dari atas ke bawah. Jangan lompat-lompat!

---

## PHASE 1: PERSIAPAN AWAL (15 menit)

### ✓ Step 1.1: Verifikasi Lokasi File
- [ ] Repository sudah di-clone: `/vercel/share/v0-project/UTS-TPD-KELOMPOK-1`
- [ ] Folder `R_SHINY_APP` sudah ada di dalam repo
- [ ] File `app.R`, `global.R`, `ui.R`, `server.R` sudah ada

**Verifikasi:**
```bash
cd /vercel/share/v0-project/R_SHINY_APP
ls -la *.R
# Output harus menunjukkan: app.R, global.R, ui.R, server.R
```

### ✓ Step 1.2: Verifikasi R & RStudio
- [ ] R sudah terinstall (v4.0+)
- [ ] RStudio sudah terinstall (optional, tapi recommended)
- [ ] Bisa akses terminal/command line

**Verifikasi:**
```bash
R --version
# Output harus menunjukkan: R version 4.x.x
```

---

## PHASE 2: KONFIGURASI DATABASE (10 menit)

### ✓ Step 2.1: Siapkan .env File
**File yang harus dikonfigurasi:** `.env` (TIDAK DI-GIT, rahasia!)

**Apa yang harus dilakukan:**
```bash
cd /vercel/share/v0-project/R_SHINY_APP
cp .env.example .env
nano .env  # atau gunakan editor favorit Anda
```

### ✓ Step 2.2: Isi Database Credentials di .env

**File:** `.env`

Buka file `.env` dan isi dengan data PostgreSQL Anda:

```env
# ============= ISI DENGAN DATA ANDA =============

# 1. Database Host (alamat server PostgreSQL)
DB_HOST=localhost              # atau IP address server Anda
                               # Contoh: 192.168.1.100 atau db.company.com

# 2. Database Port (default PostgreSQL adalah 5432)
DB_PORT=5432                   # Jangan ubah kalau standard

# 3. Database Name (nama database DWH Anda)
DB_NAME=datawarehouse_db       # Atau nama DB Anda sebenarnya
                               # Contoh: livestock_dwh, supply_intelligence

# 4. Database User (username untuk login)
DB_USER=postgres               # Atau username Anda
                               # Contoh: dwh_user, analytics

# 5. Database Password (password untuk login)
DB_PASSWORD=your_password_here # GANTI DENGAN PASSWORD ASLI!
                               # Jangan share file ini!

# ============= JANGAN UBAH (SUDAH BENAR) =============

SHAPEFILE_PATH=data/ADMINISTRAS_PROVINSI.shp
SHINY_PORT=3838
SHINY_HOST=0.0.0.0
```

**Contoh Real (untuk testing lokal):**
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=datawarehouse_db
DB_USER=postgres
DB_PASSWORD=mysecurepassword123
SHAPEFILE_PATH=data/ADMINISTRAS_PROVINSI.shp
SHINY_PORT=3838
SHINY_HOST=0.0.0.0
```

### ✓ Step 2.3: Test Koneksi Database
**Verifikasi bahwa credentials benar:**

```bash
# Dari terminal (ganti dengan nilai dari .env Anda):
psql -h localhost -U postgres -d datawarehouse_db -c "SELECT COUNT(*) FROM dim_prov;"

# Kalau berhasil, output:
#  count
# -------
#     34
# (1 row)

# Kalau gagal, output error:
# ERROR: password authentication failed for user "postgres"
# ↑ Berarti password di .env salah
```

**Troubleshooting koneksi:**
- [ ] Pastikan PostgreSQL running: `sudo systemctl status postgresql`
- [ ] Pastikan credentials benar (cek database admin)
- [ ] Pastikan database sudah ada: `psql -l`
- [ ] Pastikan schema sudah di-load: `psql -d datawarehouse_db -c "\dt"`

---

## PHASE 3: PERSIAPAN DATA SPATIAL (10 menit)

### ✓ Step 3.1: Siapkan Folder Data
**File location:** `data/ADMINISTRAS_PROVINSI.shp*`

```bash
# Buat folder data kalau belum ada
mkdir -p /vercel/share/v0-project/R_SHINY_APP/data

# Verify folder sudah ada
ls -la data/
```

### ✓ Step 3.2: Copy Shapefile ke Folder Data
**Yang harus di-copy:**

Shapefile ADMINISTRAS_PROVINSI terdiri dari beberapa file:
```
ADMINISTRAS_PROVINSI.shp      ← File utama (geometry)
ADMINISTRAS_PROVINSI.shx      ← File index
ADMINISTRAS_PROVINSI.dbf      ← File attribute
ADMINISTRAS_PROVINSI.prj      ← File projection
ADMINISTRAS_PROVINSI.cpg      ← File codepage
```

**Apa yang harus dilakukan:**
```bash
# Copy SEMUA file shapefile
cp /path/to/ADMINISTRAS_PROVINSI.shp* /vercel/share/v0-project/R_SHINY_APP/data/

# Verify semua file sudah tercopy
ls -la /vercel/share/v0-project/R_SHINY_APP/data/ADMINISTRAS_PROVINSI.*

# Output harus menunjukkan:
# ADMINISTRAS_PROVINSI.shp
# ADMINISTRAS_PROVINSI.shx
# ADMINISTRAS_PROVINSI.dbf
# ADMINISTRAS_PROVINSI.prj
# ADMINISTRAS_PROVINSI.cpg
```

### ✓ Step 3.3: Validate Shapefile
**Verifikasi shapefile bisa dibaca oleh R:**

Buka RStudio atau terminal R:
```r
library(sf)
shp <- st_read("data/ADMINISTRAS_PROVINSI.shp")
head(shp, 3)

# Seharusnya muncul data dengan kolom nama_provinsi
# Jika error "File not found" → shapefile belum di-copy
# Jika error geometry → file corrupted → copy ulang
```

---

## PHASE 4: INSTALASI R PACKAGES (5-10 menit)

### ✓ Step 4.1: Install Dependencies Otomatis
**File:** `install_packages.R`

```bash
cd /vercel/share/v0-project/R_SHINY_APP
Rscript install_packages.R

# Tunggu sampai selesai, tunggu 5-10 menit tergantung internet
# Output:
# ✓ shiny installed successfully
# ✓ RPostgres installed successfully
# ... dst
# ✓ All dependencies installed successfully!
```

### ✓ Step 4.2: Verify Installation (jika gagal)
**Kalau Step 4.1 gagal, install manual:**

```r
# Buka RStudio atau R console
packages <- c("shiny", "shinydashboard", "shinyWidgets", "shinyalert",
              "DBI", "RPostgres", "dplyr", "dbplyr", "tidyr",
              "sf", "leaflet", "leaflet.extras",
              "plotly", "ggplot2", "scales", "treemapify",
              "grid", "gridExtra", "tidyverse", "lubridate", 
              "zoo", "corrplot", "formattable")

for (pkg in packages) {
  if (!require(pkg, character.only = TRUE)) {
    install.packages(pkg)
  }
}
```

---

## PHASE 5: KONFIGURASI APLIKASI (5 menit)

### ✓ Step 5.1: Review global.R

**File:** `global.R` (line 54-60, 89-91)

**Bagian yang mungkin perlu di-adjust:**

```r
# LINE 54-60: Database Config (seharusnya OK, karena ambil dari .env)
db_config <- list(
  host = Sys.getenv("DB_HOST", "localhost"),
  port = as.numeric(Sys.getenv("DB_PORT", 5432)),
  dbname = Sys.getenv("DB_NAME", "datawarehouse_db"),
  user = Sys.getenv("DB_USER", "postgres"),
  password = Sys.getenv("DB_PASSWORD", "")
)
# ✓ Bagian ini akan otomatis baca dari .env, JANGAN diubah

# LINE 89-91: Shapefile Path
shapefile_path <- "data/ADMINISTRAS_PROVINSI.shp"
# ✓ Ini akan otomatis cari di folder data/ dari working directory
# Kalau shapefile di lokasi lain, ubah path ini
```

### ✓ Step 5.2: Review ui.R

**File:** `ui.R`

**Hanya perlu di-review, tidak perlu di-ubah:**
- [ ] Pastikan 3 tabs ada: "Executive Summary", "Analisis Sektor Riil", "Investigasi & Korelasi"
- [ ] Pastikan filter sidebar ada: Provinsi, Komoditas, Tahun, Bulan
- [ ] Pastikan "Apply Filters" button ada

**Jika ingin customize (optional):**
- Ubah title di line 3: `title = "Livestock Intelligence Dashboard"`
- Ubah warna di themes (bagian theme)
- Ubah label/placeholder di inputs

### ✓ Step 5.3: Review server.R

**File:** `server.R`

**Hanya perlu di-review, tidak perlu di-ubah:**
- [ ] Pastikan semua observers & outputs ada
- [ ] Pastika database queries tidak error

**Jika ada error, lihat comment di line 1-50 untuk penjelasan struktur**

---

## PHASE 6: COBA JALANKAN APLIKASI (5 menit)

### ✓ Step 6.1: Start Aplikasi

**Opsi A: Dari Terminal (Recommended)**
```bash
cd /vercel/share/v0-project/R_SHINY_APP
Rscript -e "shiny::runApp()"

# Output:
# Listening on http://127.0.0.1:3838
# ↑ Copy URL ini ke browser
```

**Opsi B: Dari RStudio**
1. Buka `app.R`
2. Klik tombol "Run App" (biru, atas kanan)
3. Dashboard akan otomatis terbuka di RStudio Viewer

### ✓ Step 6.2: Akses Dashboard

Buka browser ke: `http://localhost:3838`

**Kalau berhasil, seharusnya melihat:**
- [ ] Header "Livestock Intelligence Dashboard"
- [ ] 3 tabs di bagian atas
- [ ] Sidebar dengan filters di kiri
- [ ] Dashboard dengan charts/maps di tengah
- [ ] Tidak ada error message merah

### ✓ Step 6.3: Test Functionality

Lakukan test cepat:
1. [ ] Ubah filter Provinsi → charts update
2. [ ] Ubah filter Komoditas → charts update
3. [ ] Click "Apply Filters" → Loading animasi muncul
4. [ ] Tab 1 (Executive Summary) → Lihat map dengan warna-warna
5. [ ] Tab 2 (Analisis Sektor Riil) → Lihat charts dengan gap analysis
6. [ ] Tab 3 (Investigasi) → Lihat time series + correlation

---

## PHASE 7: TROUBLESHOOTING (Jika Ada Error)

### Error 1: "Database connection failed"

**Tanda:** Aplikasi tidak mau start, error message di terminal

**Solusi:**
```bash
# 1. Cek .env file ada dan readable
ls -la .env

# 2. Cek credentials di .env
cat .env

# 3. Test connection manual
psql -h <DB_HOST> -U <DB_USER> -d <DB_NAME>
# Enter password ketika diminta

# 4. Kalau masih gagal, cek PostgreSQL running
sudo systemctl status postgresql
# Kalau tidak running: sudo systemctl start postgresql

# 5. Cek database & table ada
psql -h <DB_HOST> -U <DB_USER> -d <DB_NAME> -c "SELECT COUNT(*) FROM fact_supply_resilience;"
```

**Kemungkinan penyebab:**
- [ ] Password salah → Update di .env
- [ ] Host salah (localhost vs IP address) → Update di .env
- [ ] PostgreSQL tidak running → Start service
- [ ] Database belum ada → Create atau restore dari backup
- [ ] Firewall block → Cek firewall rules

### Error 2: "Shapefile not found"

**Tanda:** Warning di terminal, map tidak muncul tapi app tetap running

**Solusi:**
```bash
# 1. Cek file ada
ls -la data/ADMINISTRAS_PROVINSI.shp*

# 2. Kalau tidak ada, copy
cp /path/to/ADMINISTRAS_PROVINSI.shp* data/

# 3. Cek nama file benar (case-sensitive di Linux)
# ADMINISTRAS_PROVINSI.shp ✓ (benar)
# administras_provinsi.shp ✗ (salah di Linux)

# 4. Restart aplikasi
# Tekan Ctrl+C di terminal, jalankan ulang
```

### Error 3: "Package not found"

**Tanda:** `Error in library(xxx): there is no package called 'xxx'`

**Solusi:**
```r
# Install package yang error
install.packages("xxx")  # ganti xxx dengan nama package

# Atau jalankan installer script:
Rscript install_packages.R
```

### Error 4: "No data" di charts

**Tanda:** Chart kosong atau "No data available"

**Solusi:**
1. Coba ubah filter:
   - Provinsi: "Nasional" (jangan spesifik)
   - Tahun: 2020-2025 (range besar)
   - Bulan: Pilih semua
2. Click "Apply Filters"

3. Kalau masih kosong, cek data di database:
```sql
-- Login ke database
psql -d datawarehouse_db

-- Check ada data?
SELECT COUNT(*) FROM fact_supply_resilience;

-- Check province names
SELECT DISTINCT nama_provinsi FROM dim_prov ORDER BY nama_provinsi;

-- Check ada kombinasi data?
SELECT COUNT(*) 
FROM fact_supply_resilience 
WHERE tahun = 2024 AND bulan = 1;
```

### Error 5: "App is slow / unresponsive"

**Solusi:**
1. Reduce filter range:
   - Tahun: 2024-2025 (jangan 2015-2025)
   - Provinsi: Specific province (jangan "Nasional")

2. Cek database performance:
```sql
-- Check indexes
SELECT * FROM pg_indexes WHERE tablename = 'fact_supply_resilience';

-- Create missing indexes if needed:
CREATE INDEX idx_fact_tahun_bulan ON fact_supply_resilience(tahun, bulan);
CREATE INDEX idx_fact_prov ON fact_supply_resilience(id_prov);
```

3. Restart PostgreSQL:
```bash
sudo systemctl restart postgresql
```

---

## CHECKLIST FINAL SEBELUM GO LIVE

Pastikan semua ini sudah OK:

- [ ] Database credentials di .env benar
- [ ] PostgreSQL running dan accessible
- [ ] Shapefile ada di `data/` folder
- [ ] Semua R packages sudah installed
- [ ] Aplikasi bisa start tanpa error
- [ ] Dashboard loading dengan data
- [ ] Semua 3 tabs bisa diakses
- [ ] Filters berfungsi dengan baik
- [ ] Map muncul dengan warna-warna (atau setidaknya tidak error)
- [ ] Charts update saat filter diubah

**Kalau semua OK:** Aplikasi siap untuk digunakan! ✓

---

## FILE MANA SAJA YANG PERLU DIKONFIGURASI - RINGKAS

| File | Konfigurasi | Bagian | Prioritas |
|------|-------------|---------|-----------|
| **`.env`** | DB credentials | Host, Port, Name, User, Password | 🔴 CRITICAL |
| **`data/ADMINISTRAS_PROVINSI.shp*`** | Copy files | Semua .shp, .shx, .dbf, .prj, .cpg | 🔴 CRITICAL |
| **`global.R`** | Review saja | Line 54-60, 89-91 | 🟡 OPTIONAL |
| **`ui.R`** | Review saja | Titles, colors | 🟡 OPTIONAL |
| **`server.R`** | Review saja | Database queries | 🟡 OPTIONAL |
| **`install_packages.R`** | Run saja | Tidak perlu edit | ✓ AUTO |

---

## QUICK START - 3 MENIT

Kalau Anda sudah pernah setup sebelumnya, ikuti ini saja:

```bash
# 1. Update .env dengan credentials (1 menit)
cd /vercel/share/v0-project/R_SHINY_APP
nano .env

# 2. Copy shapefile (30 detik)
cp /path/to/ADMINISTRAS_PROVINSI.shp* data/

# 3. Install packages (90 detik)
Rscript install_packages.R

# 4. Start app (1 menit)
Rscript -e "shiny::runApp()"

# 5. Open browser
# http://localhost:3838
```

---

**Version**: 1.0  
**Last Updated**: 2026-05-04  
**Status**: Ready to follow
