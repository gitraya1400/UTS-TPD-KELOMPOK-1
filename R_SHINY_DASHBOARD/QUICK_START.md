# ⚡ QUICK START - 5 Minute Setup

**Kelompok 1 TPD - Livestock Intelligence Dashboard**

---

## Step 1: Copy Shapefile (1 min)

```bash
# Pastikan ADMINISTRAS_PROVINSI.shp ada di sini:
cp /path/to/ADMINISTRAS_PROVINSI.shp* R_SHINY_DASHBOARD/data/

# Verifikasi:
ls R_SHINY_DASHBOARD/data/ADMINISTRAS_PROVINSI.*
# Output harus:
# ADMINISTRAS_PROVINSI.shp
# ADMINISTRAS_PROVINSI.shx
# ADMINISTRAS_PROVINSI.dbf
# ADMINISTRAS_PROVINSI.prj (opsional)
```

---

## Step 2: Configure Database (1 min)

```bash
cd R_SHINY_DASHBOARD
cp .env.example .env

# Edit .env dengan text editor
nano .env  # atau gunakan VS Code/RStudio
```

**Isi dengan:**
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=datawarehouse_db
DB_USER=postgres
DB_PASSWORD=your_postgres_password
```

---

## Step 3: Install R Packages (2 min)

**Option A: Auto-install**
```bash
Rscript install_dependencies.R
```

**Option B: Manual (di R console)**
```r
install.packages(c("shiny", "shinydashboard", "shinyWidgets", 
                   "tidyverse", "plotly", "DT", "sf", "leaflet",
                   "RPostgres", "DBI", "pool", "scales", "lubridate"))
```

---

## Step 4: Verify Database (30 sec)

Di R console:
```r
source("config.R")
con <- create_db_connection()
dbListTables(con)

# Output harus include:
# [1] "fact_supply_resilience" "dim_prov" "dim_komoditas" "dim_waktu"
```

---

## Step 5: Run Dashboard (30 sec)

**Option A: Dari RStudio**
1. Buka `app.R`
2. Klik "Run App" button

**Option B: Dari Terminal**
```bash
Rscript -e "shiny::runApp()"
```

**Open di Browser:**
```
http://localhost:3838
```

---

## ✅ You're Done!

Dashboard should be running dengan 8 tabs:
1. Executive Summary
2. Early Warning System
3. Price-Disease Correlation
4. Supply-Demand Gap
5. Spatial Risk Map
6. Supply Dependency
7. Data Explorer
8. Documentation

---

## 🎨 First Things to Try

### Test Filters
- Select province dari dropdown
- Change commodity radio button
- Adjust year slider
- Click "Apply Filters (Query)"

### Explore Maps
- Click province pada choropleth map
- Hover untuk see tooltip
- Zoom dengan mouse scroll

### Check Analyses
- Each tab menampilkan different OLAP analysis
- All visualizations interactive (Plotly)
- Tables searchable & sortable

### Export Data
- Go to "Data Explorer" tab
- Click "Download as CSV" or "Excel"

---

## 🐛 If Something Goes Wrong

### Error: "object 'db_con' not found"
```bash
# Restart R session (Ctrl+Shift+F10 di RStudio)
# Or reload package:
Rscript -e "shiny::runApp()"
```

### Error: "Cannot find shapefile"
```bash
# Verify path
ls R_SHINY_DASHBOARD/data/
# Should show ADMINISTRAS_PROVINSI.* files

# If not, copy them:
cp /actual/path/ADMINISTRAS_PROVINSI.* R_SHINY_DASHBOARD/data/
```

### Error: "Connection refused"
```bash
# Check PostgreSQL running
psql -h localhost -U postgres

# If not running:
# Linux: sudo service postgresql start
# Mac: brew services start postgresql
# Windows: Start PostgreSQL service
```

### Dashboard loads slowly
- May happen first time while loading shapefile
- Wait 30 seconds
- If still slow, check internet connection (for map tiles)

---

## 📊 OLAP Operations Quick Reference

| Operation | What | Where |
|-----------|------|-------|
| **SLICING** | Filter 1 dimension | Provinsi dropdown |
| **DICING** | Filter multiple dims | Province + Commodity + Year + Quarter |
| **ROLL-UP** | Aggregate higher | "Top 10 Provinsi" charts |
| **DRILL-DOWN** | Detail lower | "Timeline/Monthly" tables |

---

## 🔑 Key Features at a Glance

| Feature | Location | Use Case |
|---------|----------|----------|
| **Risk Index** | Executive Summary | See current crisis risk |
| **Top Risk Provs** | Early Warning | Identify high-risk areas |
| **Price-Disease Corr** | Correlation Tab | Analyze harga-wabah link |
| **Supply Gap** | Gap Analysis | Find deficit regions |
| **Choropleth Map** | Spatial Map | Visualize risk geographically |
| **Pareto Charts** | Supply Dependency | Identify key suppliers |
| **Data Table** | Data Explorer | Access raw data |

---

## 📞 Get Help

- **Setup issues?** → Read README.md
- **Technical questions?** → Check TECHNICAL.md
- **How to deploy?** → See DEPLOYMENT.md
- **OLAP concept?** → Tab 8 Documentation

---

## ⏱️ Performance Tips

- First load: ~2-3 seconds (normal)
- Filter application: ~1 second
- Chart rendering: instant (Plotly is fast)
- Spatial map: ~5 seconds (shapefile large)
- If slow: reduce date range in filters

---

**You're all set! Happy analyzing! 🚀**
