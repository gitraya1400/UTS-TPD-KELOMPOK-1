# Technical Documentation - Livestock Intelligence Dashboard

## Spatial Join Implementation (Without Latitude/Longitude)

### Problem Statement
Database PostgreSQL kami TIDAK memiliki kolom Latitude dan Longitude. Oleh karena itu, untuk implementasi peta interaktif (choropleth), kami menggunakan spatial join antara:
- **fact_supply_resilience** (data risk dari database)
- **ADMINISTRAS_PROVINSI.shp** (file shapefile lokal dengan geometry)

### Join Key: Nama Provinsi (Standardized)

```r
# Step 1: Load spatial data
spatial_data <- st_read("data/ADMINISTRAS_PROVINSI.shp", quiet = TRUE)

# Step 2: Standardize province names to UPPERCASE for matching
spatial_data$nama_provinsi <- toupper(trimws(spatial_data$Provinsi))

# Step 3: Query risk data dari database
risk_data <- dbGetQuery(con, "
  SELECT 
    p.nama_provinsi,
    AVG(f.supply_risk_index) AS risk_index,
    SUM(f.sum_jumlah_sakit) AS total_sick
  FROM fact_supply_resilience f
  JOIN dim_prov p ON f.prov_key = p.prov_key
  JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
  WHERE k.nama_komoditas = 'Sapi'
  GROUP BY p.nama_provinsi
")

# Step 4: Standardize database data
risk_data$nama_provinsi <- toupper(trimws(risk_data$nama_provinsi))

# Step 5: Spatial join using left_join (keep all geometries)
spatial_joined <- spatial_data %>%
  left_join(
    st_drop_geometry(risk_data),
    by = "nama_provinsi",
    match.fun = function(x, y) x == y
  )

# Step 6: Render dengan Leaflet
leaflet(spatial_joined) %>%
  addTiles() %>%
  addPolygons(
    fillColor = ~leaflet_risk_palette(risk_index),
    fillOpacity = 0.7,
    weight = 2,
    color = "white",
    label = labels
  )
```

### Important Notes:
1. **Join Type**: LEFT JOIN (pastikan semua geometry tetap tertampil, meskipun tidak ada data risiko)
2. **Name Standardization**: Gunakan `toupper()` dan `trimws()` untuk konsistensi
3. **Geometry Handling**: Gunakan `st_drop_geometry()` pada risk_data sebelum join agar tidak duplikat geometry
4. **Column Name**: Sesuaikan nama kolom provinsi di shapefile (bisa "Provinsi", "PROVINSI", "Prov", dll)

---

## Query Pushdown Optimization

### Strategy: In-Database Processing

Prinsip dasar: **Lakukan semua filtering, grouping, dan aggregation di database PostgreSQL, baru tarik hasil ke R memory**.

```r
# ❌ ANTI-PATTERN: Full table scan
all_data <- dbReadTable(con, "fact_supply_resilience")  # Loads millions of rows
filtered <- all_data %>%
  filter(prov_key == 12) %>%
  group_by(bulan) %>%
  summarise(avg_risk = mean(supply_risk_index))

# ✅ PATTERN: Query Pushdown
# All operations happen in PostgreSQL engine, only results returned
filtered <- tbl(con, "fact_supply_resilience") %>%
  filter(prov_key == 12) %>%
  group_by(bulan) %>%
  summarise(avg_risk = mean(supply_risk_index)) %>%
  collect()  # ← collect() is the LAST operation

# Verify the generated SQL
show_query(filtered)
```

### Benefits:
- ⚡ **Speed**: Database engines optimized for large data processing
- 💾 **Memory**: Only aggregated result transferred to R
- 🔍 **Transparency**: Can inspect generated SQL with `show_query()`

### Implementation in Dashboard:

```r
query_supply_resilience <- function(prov = "Nasional", komoditas = "Sapi", 
                                    year_range = c(2020, 2025), 
                                    months = 1:12) {
  
  # Create lazy evaluation
  fact_tbl <- tbl(con, "fact_supply_resilience")
  prov_tbl <- tbl(con, "dim_prov")
  waktu_tbl <- tbl(con, "dim_waktu")
  komoditas_tbl <- tbl(con, "dim_komoditas")
  
  # Build query (still lazy, not executed yet)
  query <- fact_tbl %>%
    left_join(prov_tbl, by = "prov_key") %>%
    left_join(waktu_tbl, by = "waktu_key") %>%
    left_join(komoditas_tbl, by = "komoditas_key")
  
  # Apply SLICING filters
  if (prov != "Nasional") {
    query <- query %>%
      filter(nama_provinsi == prov)
  }
  
  # Apply DICING filters
  query <- query %>%
    filter(nama_komoditas == komoditas) %>%
    filter(tahun >= year_range[1] & tahun <= year_range[2]) %>%
    filter(bulan %in% months)
  
  # ← ALL of above still lazy, executed in PostgreSQL
  # ← Only execute (transfer) when we collect()
  result <- query %>%
    collect()
  
  return(result)
}
```

---

## Database Indexes for Performance

### Recommended Indexes (already defined in schema):

```sql
-- Fact table indexes
CREATE INDEX idx_fact_prov ON public.fact_supply_resilience (prov_key);
CREATE INDEX idx_fact_waktu ON public.fact_supply_resilience (waktu_key);
CREATE INDEX idx_fact_komoditas ON public.fact_supply_resilience (komoditas_key);
CREATE INDEX idx_fact_risk ON public.fact_supply_resilience (supply_risk_index DESC);

-- For common queries
CREATE INDEX idx_fact_prov_waktu ON public.fact_supply_resilience (prov_key, waktu_key);
CREATE INDEX idx_fact_risk_desc_prov ON public.fact_supply_resilience (supply_risk_index DESC, prov_key);
```

### Check index usage:

```sql
-- View index statistics
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;

-- Analyze table for query planning
ANALYZE fact_supply_resilience;
```

---

## OLAP Operations Implementation

### 1. SLICING (Filter Single Dimension)

```r
# SLICING: Select only Sapi in Jawa Timur
sliced_data <- fact_data %>%
  filter(nama_komoditas == "Sapi") %>%
  filter(nama_provinsi == "Jawa Timur") %>%
  collect()

# Generated SQL:
# SELECT * FROM fact_supply_resilience f
# JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
# JOIN dim_prov p ON f.prov_key = p.prov_key
# WHERE k.nama_komoditas = 'Sapi' AND p.nama_provinsi = 'Jawa Timur'
```

### 2. DICING (Filter Multiple Dimensions)

```r
# DICING: Select Sapi, Jan-Jun, 2024-2025, only high-risk provinces
diced_data <- fact_data %>%
  filter(nama_komoditas == "Sapi") %>%
  filter(tahun %in% c(2024, 2025)) %>%
  filter(bulan %in% 1:6) %>%
  filter(supply_risk_index > 0.67) %>%
  collect()
```

### 3. ROLL-UP (Aggregate to Higher Level)

```r
# ROLL-UP: Aggregate from monthly to provincial level
rolled_up <- fact_data %>%
  group_by(nama_provinsi) %>%  # Remove bulan dimension
  summarise(
    avg_risk = mean(supply_risk_index),
    total_sick = sum(sum_jumlah_sakit),
    .groups = "drop"
  ) %>%
  collect()

# Or aggregate to national level (remove both provinsi & bulan)
national_agg <- fact_data %>%
  summarise(
    avg_risk = mean(supply_risk_index),
    total_sick = sum(sum_jumlah_sakit),
    .groups = "drop"
  ) %>%
  collect()
```

### 4. DRILL-DOWN (Disaggregate to Lower Level)

```r
# Start with annual data
annual <- fact_data %>%
  group_by(tahun, nama_provinsi) %>%
  summarise(avg_risk = mean(supply_risk_index)) %>%
  collect()

# DRILL-DOWN to monthly level
monthly <- fact_data %>%
  group_by(tahun, bulan, nama_provinsi) %>%
  summarise(avg_risk = mean(supply_risk_index)) %>%
  collect()

# User sees finer granularity of same data
```

### 5. PIVOT (Change Perspective)

```r
# Original: Long format (rows = province-month combinations)
long_data <- fact_data %>%
  select(nama_provinsi, bulan, supply_risk_index) %>%
  collect()

# PIVOT to wide format (rows = provinces, columns = months)
wide_data <- long_data %>%
  pivot_wider(
    names_from = bulan,
    names_prefix = "Month_",
    values_from = supply_risk_index
  )
```

---

## Reactive Programming Patterns

### Pattern 1: Single Reactive Expression

```r
filtered_data <- reactive({
  input$btn_apply
  
  # All UI inputs inside reactive {} are tracked for changes
  data <- tbl(con, "fact_supply_resilience") %>%
    filter(..conditions..) %>%
    collect()
  
  return(data)
})

# Use in outputs
output$chart <- renderPlotly({
  data <- filtered_data()  # Automatically re-evaluates when input changes
  # Create visualization
})
```

### Pattern 2: Dependent Reactive Expressions

```r
# Primary reactive data
filtered_data <- reactive({ ... })

# Dependent reactives
top_risk <- reactive({
  data <- filtered_data()  # Depends on filtered_data()
  
  top <- data %>%
    group_by(nama_provinsi) %>%
    summarise(avg_risk = mean(supply_risk_index)) %>%
    arrange(desc(avg_risk)) %>%
    head(5)
  
  return(top)
})

# When input changes:
# 1. filtered_data() updates
# 2. top_risk() automatically recalculates (depends on filtered_data)
# 3. All outputs using top_risk() automatically re-render
```

### Pattern 3: Avoid Reactive Recalculation

```r
# ❌ WRONG: Recalculates database query for EVERY output
output$chart1 <- renderPlotly({
  data <- query_supply_resilience(...)  # DB query
  # visualization
})

output$chart2 <- renderPlotly({
  data <- query_supply_resilience(...)  # DB query again!
  # visualization
})

# ✅ CORRECT: Single reactive, reused by multiple outputs
data <- reactive({
  query_supply_resilience(...)  # DB query once
})

output$chart1 <- renderPlotly({
  data <- data()  # Use cached result
})

output$chart2 <- renderPlotly({
  data <- data()  # Reuse same result
})
```

---

## Supply Risk Index Calculation

### Formula

```
supply_risk_index = (price_gap_scaled + health_impact_scaled + supply_strain_scaled) / 3

All components scaled to [0, 1] using MIN-MAX normalization:

scaled_value = (value - min) / (max - min)
```

### Components Explanation

#### 1. Price Gap
```
price_gap = (avg_harga - harga_baseline) / harga_baseline

- Mengukur deviasi harga AKTUAL dari BASELINE pemerintah
- Positif = harga naik (premium/scarcity)
- Negatif = harga turun (diskon/surplus)
- Indicator: Jika naik, menandakan masalah supply
```

#### 2. Health Impact  
```
health_impact = (sum_jumlah_sakit + sum_jumlah_mati) / populasi_ternak

- Mengukur PROPORSI hewan sakit/mati
- Range: 0 (no disease) to 1 (population extinct)
- Indicator: Jika tinggi, production capacity terganggu
```

#### 3. Supply Strain
```
supply_strain = sum_vol_mutasi / avg_permintaan_bulanan

- Mengukur BEBAN pengiriman vs kebutuhan
- < 1.0 = undersupply (deficit)
- = 1.0 = balanced
- > 1.0 = oversupply (surplus)
- Indicator: Jika < 1.0, ada gap yang harus dipenuhi dari cadangan
```

### Interpretation

```
Risk Index Range:
- 0.00-0.33: GREEN (Aman) ✓
  → Price stable, disease low, supply adequate
  
- 0.33-0.67: ORANGE (Peringatan) ⚠
  → Some stress indicators present
  → Monitor closely
  
- 0.67-1.00: RED (Bahaya) ✗
  → Critical situation
  → Immediate intervention needed
```

---

## Performance Monitoring

### Query Execution Time

```r
# Measure query performance
system.time({
  result <- tbl(con, "fact_supply_resilience") %>%
    filter(prov_key == 12) %>%
    group_by(bulan) %>%
    summarise(avg_risk = mean(supply_risk_index)) %>%
    collect()
})

# Output:
# user  system elapsed
# 0.123  0.045   0.234   ← elapsed time in seconds
```

### Database Query Analysis

```sql
-- Explain query plan to optimize
EXPLAIN ANALYZE
SELECT 
  p.nama_provinsi,
  AVG(f.supply_risk_index) as avg_risk
FROM fact_supply_resilience f
JOIN dim_prov p ON f.prov_key = p.prov_key
WHERE p.prov_key = 12
GROUP BY p.nama_provinsi;

-- Look for:
-- - Sequential Scan (slow, consider index)
-- - Index Scan (fast, good)
-- - high "Rows" number (filtering needed)
```

### Memory Usage in R

```r
# Check memory used by reactive data
pryr::object_size(filtered_data_object)

# If > 100MB, consider:
# - More aggressive filtering
# - Aggregating at database level
# - Reducing time range
```

---

## Common Errors & Solutions

### Error 1: "NA/NaN in scalars not allowed"

```r
# Cause: Missing values in correlation calculation
# Solution: Use use="complete.obs"

cor(price_vec, sick_vec, use = "complete.obs")  # ✓ Correct
cor(price_vec, sick_vec)  # ✗ Fails if NAs present
```

### Error 2: "Join key not found"

```r
# Cause: Column name mismatch in join
# Solution: Verify column names match exactly

# ❌ Wrong
left_join(data1, data2, by = "Province")  # Column called "Provinsi" in data2

# ✓ Correct
left_join(data1, data2, by = c("Provinsi" = "Provinsi"))
```

### Error 3: "could not translate expression to SQL"

```r
# Cause: Using R function that dbplyr doesn't support
# Solution: Move to R side before database query

# ❌ Causes error
data %>%
  filter(custom_function(column) > 0) %>%  # Can't translate custom function
  collect()

# ✓ Correct
data %>%
  collect() %>%
  filter(custom_function(column) > 0)
```

---

## Testing Queries

### Test Query 1: National Risk Index

```sql
SELECT 
  AVG(supply_risk_index) as national_risk,
  MIN(supply_risk_index) as min_risk,
  MAX(supply_risk_index) as max_risk
FROM fact_supply_resilience f
JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
WHERE k.nama_komoditas = 'Sapi'
  AND EXTRACT(YEAR FROM NOW()) - f.tahun <= 1;
```

### Test Query 2: Top Risk Provinces

```sql
SELECT 
  p.nama_provinsi,
  AVG(f.supply_risk_index) as avg_risk,
  COUNT(*) as data_points
FROM fact_supply_resilience f
JOIN dim_prov p ON f.prov_key = p.prov_key
JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
WHERE k.nama_komoditas = 'Sapi'
GROUP BY p.prov_key, p.nama_provinsi
ORDER BY avg_risk DESC
LIMIT 5;
```

### Test Query 3: Supply-Demand Gap

```sql
SELECT 
  p.nama_provinsi,
  ROUND(AVG(f.sum_vol_mutasi), 2) as avg_supply_ekor,
  ROUND(AVG(f.avg_permintaan_bulanan), 2) as avg_demand_ekor,
  ROUND(AVG(f.sum_vol_mutasi - f.avg_permintaan_bulanan), 2) as gap_ekor
FROM fact_supply_resilience f
JOIN dim_prov p ON f.prov_key = p.prov_key
GROUP BY p.prov_key, p.nama_provinsi
ORDER BY gap_ekor ASC;
```

---

## Maintenance Tasks

### Daily
- Monitor application error logs
- Check database connection status

### Weekly
- Analyze slow queries using EXPLAIN ANALYZE
- Review application crash logs
- Test spatial join accuracy for new data

### Monthly
- Update database statistics: `ANALYZE fact_supply_resilience;`
- Review index fragmentation: `REINDEX INDEX idx_fact_prov;`
- Backup database

### Quarterly
- Performance tuning review
- Update documentation
- Test disaster recovery procedures

---

**Document Version**: 1.0  
**Last Updated**: 2026-05-04
