# ============================================================
# EXPORT DATA WAREHOUSE → CSV
# Jalankan script ini di komputer lokal setiap kali ada
# perubahan data, lalu overwrite file data/olap_cube.csv
# ============================================================

library(DBI)
library(RPostgres)

DB_CONFIG <- list(
  host     = "localhost",
  port     = 5432,
  dbname   = "datawarehouse_db",
  user     = "postgres",
  password = "-RqorROOT44"   # ganti sesuai env
)

cat("Menghubungkan ke database...\n")
con <- dbConnect(
  RPostgres::Postgres(),
  host     = DB_CONFIG$host,
  port     = DB_CONFIG$port,
  dbname   = DB_CONFIG$dbname,
  user     = DB_CONFIG$user,
  password = DB_CONFIG$password
)

cat("Mengambil data dari DWH...\n")
query <- "
  SELECT
    f.*,
    p.id_prov, p.nama_provinsi,
    w.tahun, w.bulan, w.kuartal, w.nama_bulan,
    k.id_komoditas, k.nama_komoditas
  FROM fact_supply_resilience f
  JOIN dim_prov       p ON f.prov_key       = p.prov_key
  JOIN dim_waktu      w ON f.waktu_key       = w.waktu_key
  JOIN dim_komoditas  k ON f.komoditas_key   = k.komoditas_key
  ORDER BY w.tahun, w.bulan, p.nama_provinsi
"

df <- dbGetQuery(con, query)
dbDisconnect(con)

# Buat folder data/ kalau belum ada
if (!dir.exists("data")) dir.create("data")

# Simpan ke CSV
write.csv(df, "data/olap_cube.csv", row.names = FALSE, fileEncoding = "UTF-8")

cat("Selesai! Data tersimpan di: data/olap_cube.csv\n")
cat("Jumlah baris:", nrow(df), "\n")
cat("Kolom:", paste(names(df), collapse=", "), "\n")
cat("\nSelanjutnya: deploy ulang app ke shinyapps.io\n")



