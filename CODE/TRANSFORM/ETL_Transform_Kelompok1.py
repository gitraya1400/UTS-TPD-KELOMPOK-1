#!/usr/bin/env python
# coding: utf-8

# # ETL Pipeline: Livestock Intelligence — FASE 2 (TRANSFORM)
# **Laporan Praktikum Teknologi Perekayasaan Data — Kelompok 1 (3SI1)**
# 
# ---
# 
# ## Scope Transform
# 
# Fase ini mengambil data **as-is** dari *Staging Area* (`staging_db` PostgreSQL) yang telah diisi pada Fase Extract, kemudian melakukan seluruh proses transformasi menggunakan **PySpark** hingga menghasilkan tabel fakta `fact_supply_resilience` yang siap di-load ke *Data Warehouse*.
# 
# ### Alur Transform:
# ```
# staging_db (PostgreSQL)
#     │
#     ├── [LANGKAH 1] Cleaning & Merge BPS (API + Dummy)
#     ├── [LANGKAH 2] Normalisasi & Unpivot → 4 tabel (ref_wilayah, ref_komoditas, tr_demografi, tr_statistik)
#     ├── [LANGKAH 3] Preprocessing Lanjutan (Standardisasi provinsi, Harmonisasi tanggal, Imputasi)
#     ├── [LANGKAH 4] Bangun Tabel Dimensi (dim_prov, dim_komoditas, dim_waktu)
#     ├── [LANGKAH 5A] Agregasi iSIKHNAS & PIHPS
#     ├── [LANGKAH 5B] Normalisasi & Konversi Data BPS
#     ├── [LANGKAH 5C] Integrasi (INNER JOIN Agregasi + BPS)
#     └── [LANGKAH 5D] Hitung supply_risk_index → fact_supply_resilience
# ```

# In[ ]:


import os
# SET DULU (HARUS PALING ATAS)
os.environ["PYSPARK_PYTHON"] = r"C:\laragon\bin\python\python-3.10\python.exe"
os.environ["PYSPARK_DRIVER_PYTHON"] = r"C:\laragon\bin\python\python-3.10\python.exe"
os.environ["HADOOP_HOME"] = "C:/hadoop"
os.environ["PATH"] += ";C:/hadoop/bin"
import warnings
warnings.filterwarnings('ignore')

from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DoubleType, IntegerType, LongType, StringType, DateType, TimestampType
)
from pyspark.sql.window import Window
PG_USER     = 'postgres'
PG_PASS     = '-RqorROOT44'
PG_HOST     = 'localhost'
PG_PORT     = '5432'
STAGING_DB  = 'staging_db'

PG_JDBC_URL  = f"jdbc:postgresql://{PG_HOST}:{PG_PORT}/{STAGING_DB}"
PG_JDBC_PROPS = {
    "user":     PG_USER,
    "password": PG_PASS,
    "driver":   "org.postgresql.Driver"
}

# ── INISIALISASI SPARK SESSION ──────────────────────────
# Pastikan postgresql JDBC driver tersedia.

JDBC_JAR = "D:/STIS SEM 6/TPD/TPD UTS KELOMPOK 1/postgresql-42.7.11.jar"


try:
    spark.stop()
except:
    pass

spark = (SparkSession.builder
    .appName("Livestock Intelligence — Transform")
    .config("spark.jars", JDBC_JAR)
    .config("spark.driver.extraClassPath", JDBC_JAR)
    .config("spark.executor.extraClassPath", JDBC_JAR)
    .config("spark.sql.legacy.timeParserPolicy", "LEGACY")
    .config("spark.driver.memory", "6g")               # ← naik dari 4g
    .config("spark.driver.maxResultSize", "2g")        # ← tambah
    .config("spark.sql.shuffle.partitions", "4")       # ← tambah
    .config("spark.driver.host", "127.0.0.1")
    .config("spark.driver.bindAddress", "127.0.0.1")
    .config("spark.python.worker.reuse", "false")
    .config("spark.hadoop.fs.file.impl", "org.apache.hadoop.fs.RawLocalFileSystem")
    .config("spark.hadoop.fs.file.impl.disable.cache", "true")
    .config("spark.hadoop.io.native.lib.available", "false")
    .getOrCreate())

spark.sparkContext.setLogLevel("WARN")
print("✅ SparkSession berhasil diinisialisasi.")
print(f"   Spark version : {spark.version}")
print(f"   JDBC URL      : {PG_JDBC_URL}")


# In[105]:


print(spark.sparkContext._conf.get("spark.jars"))


# In[106]:


# =========================================================
# CELL 2 · HELPER FUNCTIONS
# =========================================================

def read_staging(table_name: str):
    """Membaca tabel dari staging_db PostgreSQL via JDBC."""
    df = (spark.read
          .format("jdbc")
          .option("url",      PG_JDBC_URL)
          .option("dbtable",  f"public.{table_name}")
          .option("user",     PG_USER)
          .option("password", PG_PASS)
          .option("driver",   "org.postgresql.Driver")
          .load())
    print(f"  📥 {table_name:<45} → {df.count():>6} baris, {len(df.columns)} kolom")
    return df

def show_info(df, label: str, n: int = 5):
    """Menampilkan info singkat dataframe."""
    print(f"\n{'='*60}")
    print(f"  {label}  |  {df.count()} baris × {len(df.columns)} kolom")
    print(f"{'='*60}")
    df.printSchema()
    df.show(n, truncate=False)

print("✅ Helper functions siap.")


# In[107]:


# =========================================================
# CELL 3 · LOAD SEMUA TABEL DARI STAGING_DB
# =========================================================
print("🔄 Memuat tabel staging dari PostgreSQL...\n")

# ── BPS ─────────────────────────────────────────────────
sdf_bps_api   = read_staging("staging_bps_api_raw")
sdf_bps_dummy = read_staging("staging_bps_dummy_raw")

# ── iSIKHNAS ────────────────────────────────────────────
sdf_ref_hewan    = read_staging("staging_isikhnas_ref_hewan")
sdf_ref_wilayah  = read_staging("staging_isikhnas_ref_wilayah")
sdf_mutasi       = read_staging("staging_isikhnas_tr_mutasi")
sdf_laporan      = read_staging("staging_isikhnas_tr_laporan_sakit")
sdf_lab          = read_staging("staging_isikhnas_tr_hasil_lab")
sdf_rph          = read_staging("staging_isikhnas_tr_rph")

# ── PIHPS ────────────────────────────────────────────────
sdf_pihps        = read_staging("staging_pihps_raw")

print("\n✅ Semua tabel staging berhasil dimuat.")


# ---
# ## LANGKAH 1 — Cleaning & Merge Data BPS
# 
# Data BPS API masuk sebagai teks mentah. Perlu membersihkan format angka (titik ribuan, koma desimal) dan mengonversi ke tipe numerik sebelum bisa di-merge.

# In[108]:


# =========================================================
# CELL 4 · LANGKAH 1A — CLEANING BPS API RAW
# =========================================================
# Kolom dari staging_bps_api_raw masih TEXT semua.
# Format angka BPS: titik (.) = pemisah ribuan, koma (,) = desimal

def clean_bps_num(df, col_name: str):
    """Hapus titik ribuan, ganti koma desimal → cast float."""
    return (df
        .withColumn(col_name,
            F.regexp_replace(F.col(col_name), r'\.', '')   # hapus titik ribuan
        )
        .withColumn(col_name,
            F.regexp_replace(F.col(col_name), ',', '.')     # ganti koma → titik
        )
        .withColumn(col_name, F.col(col_name).cast(DoubleType()))
    )

numeric_api_cols = [
    "jumlah_penduduk",
    "populasi_sapi",
    "populasi_ayam",
    "produksi_daging_ayam"
]

sdf_bps_api_clean = sdf_bps_api
for c in numeric_api_cols:
    sdf_bps_api_clean = clean_bps_num(sdf_bps_api_clean, c)

# Cast tahun
sdf_bps_api_clean = sdf_bps_api_clean.withColumn("tahun", F.col("tahun").cast(IntegerType()))

print("✅ Cleaning BPS API selesai.")
show_info(sdf_bps_api_clean, "BPS API — setelah cleaning")


# In[109]:


# =========================================================
# CELL 5 · LANGKAH 1B — CLEANING BPS DUMMY RAW
# =========================================================
# Dummy sudah bertipe numerik dari staging, tapi perlu standarisasi nama kolom
# agar bisa di-merge (suffix _dummy akan dipertahankan sampai merge selesai).

sdf_bps_dummy_clean = sdf_bps_dummy.withColumn(
    "tahun", F.col("tahun").cast(IntegerType())
)

print("✅ Cleaning BPS Dummy selesai.")
show_info(sdf_bps_dummy_clean, "BPS Dummy — setelah cleaning", n=3)


# In[110]:


# =========================================================
# CELL 6 · LANGKAH 1C — MERGE BPS API + DUMMY
# =========================================================
# JOIN pada (provinsi, tahun).
# Kolom dari API menjadi sumber utama; kolom tambahan diambil dari dummy.

sdf_bps_master = (sdf_bps_api_clean.alias("api")
    .join(
        sdf_bps_dummy_clean.alias("dum"),
        on=["provinsi", "tahun"],
        how="inner"
    )
    # Pilih & rename kolom final
    .select(
        F.col("api.provinsi"),
        F.col("api.tahun"),
        F.col("api.jumlah_penduduk").alias("jumlah_penduduk"),
        F.col("api.populasi_sapi").alias("populasi_sapi"),
        F.col("api.populasi_ayam").alias("populasi_ayam"),
        F.col("api.produksi_daging_ayam").alias("produksi_daging_ayam"),
        # Kolom eksklusif dari dummy
        F.col("dum.populasi_sapi_dummy"),
        F.col("dum.populasi_ayam_dummy"),
        F.col("dum.produksi_daging_sapi_dummy").alias("produksi_daging_sapi"),
        F.col("dum.produksi_daging_ayam_dummy"),
        F.col("dum.konsumsi_daging_sapi_dummy").alias("konsumsi_daging_sapi"),
        F.col("dum.konsumsi_daging_ayam_dummy").alias("konsumsi_daging_ayam"),
        F.col("dum.permintaan_daging_sapi_dummy").alias("permintaan_daging_sapi"),
        F.col("dum.permintaan_daging_ayam_dummy").alias("permintaan_daging_ayam"),
        F.col("dum.jumlah_ternak_sapi_potong_dummy").alias("jumlah_ternak_sapi_potong"),
        F.col("dum.jumlah_ternak_ayam_potong_dummy").alias("jumlah_ternak_ayam_potong"),
        F.col("dum.harga_baseline_sapi_dummy").alias("harga_baseline_sapi"),
        F.col("dum.harga_baseline_ayam_dummy").alias("harga_baseline_ayam"),
        F.col("dum.growth_populasi_dummy").alias("growth_populasi"),
    )
)

sdf_bps_master.cache()
print(f"✅ BPS Master setelah merge: {sdf_bps_master.count()} baris")
sdf_bps_master.show(5, truncate=False)


# ---
# ## LANGKAH 2 — Normalisasi Tabel BPS & Unpivot
# 
# BPS master dipecah menjadi 4 tabel:
# | Tabel | Isi |
# |---|---|
# | `ref_wilayah` | ID & nama provinsi |
# | `ref_komoditas` | ID & nama komoditas (Sapi, Ayam) |
# | `tr_demografi` | Penduduk & growth per wilayah-tahun |
# | `tr_statistik` | Populasi & produksi per wilayah-tahun-komoditas (hasil unpivot) |

# In[111]:


# =========================================================
# CELL 7 · LANGKAH 2A — TABEL ref_wilayah (dari BPS master)
# =========================================================
# DISTINCT provinsi, diurutkan alfabetis, beri id_wilayah berurutan.

window_prov = Window.orderBy("provinsi")

sdf_ref_wilayah_bps = (sdf_bps_master
    .select("provinsi").distinct()
    .orderBy("provinsi")
    .withColumn("id_wilayah", F.row_number().over(window_prov))
    .select("id_wilayah", "provinsi")
)

sdf_ref_wilayah_bps.cache()
print(f"✅ ref_wilayah BPS: {sdf_ref_wilayah_bps.count()} provinsi")
sdf_ref_wilayah_bps.show(40, truncate=False)


# In[112]:


# =========================================================
# CELL 8 · LANGKAH 2B — TABEL ref_komoditas
# =========================================================
from pyspark.sql.types import StructType, StructField

ref_komoditas_data = [(1, "Sapi"), (2, "Ayam")]
sdf_ref_komoditas = spark.createDataFrame(ref_komoditas_data, ["id_komoditas", "nama_komoditas"])

print("✅ ref_komoditas:")
sdf_ref_komoditas.show()


# In[113]:


# =========================================================
# CELL 9 · LANGKAH 2C — MAPPING id_wilayah ke BPS Master
# =========================================================
# JOIN tabel utama dengan ref_wilayah → inject id_wilayah → drop kolom teks provinsi

sdf_bps_mapped = (sdf_bps_master.alias("bps")
    .join(sdf_ref_wilayah_bps.alias("ref"), on="provinsi", how="left")
    .drop("provinsi")   # Dari titik ini mesin hanya berurusan dengan angka
)

print(f"✅ BPS Master setelah mapping: {sdf_bps_mapped.count()} baris")
print("Kolom:", sdf_bps_mapped.columns)


# In[114]:


# =========================================================
# CELL 10 · LANGKAH 2D — TABEL tr_demografi
# =========================================================
# Subset kolom kependudukan. Buang duplikasi (karena 1 baris sudah unik per
# wilayah-tahun pada BPS master).

sdf_tr_demografi = (sdf_bps_mapped
    .select("id_wilayah", "tahun", "jumlah_penduduk", "growth_populasi")
    .dropDuplicates(["id_wilayah", "tahun"])
)

sdf_tr_demografi.cache()
print(f"✅ tr_demografi: {sdf_tr_demografi.count()} baris")
sdf_tr_demografi.show(5)


# In[115]:


# =========================================================
# CELL 11 · LANGKAH 2E — TABEL tr_statistik (UNPIVOT / MELT)
# =========================================================
# Unpivot kolom populasi & produksi dari wide → long per komoditas.

# ── SAPI ──
sdf_sapi = (sdf_bps_mapped.select(
    "id_wilayah", "tahun",
    F.lit(1).alias("id_komoditas"),
    F.coalesce(F.col("populasi_sapi"), F.col("populasi_sapi_dummy")).alias("populasi"),
    F.col("produksi_daging_sapi").alias("produksi_daging"),
    F.col("konsumsi_daging_sapi").alias("konsumsi_daging"),
    F.col("permintaan_daging_sapi").alias("permintaan_daging"),
    F.col("jumlah_ternak_sapi_potong").alias("jumlah_ternak_potong"),
    F.col("harga_baseline_sapi").cast(DoubleType()).alias("harga_baseline"),
))

# ── AYAM ──
sdf_ayam = (sdf_bps_mapped.select(
    "id_wilayah", "tahun",
    F.lit(2).alias("id_komoditas"),
    F.coalesce(F.col("populasi_ayam"), F.col("populasi_ayam_dummy")).alias("populasi"),
    F.coalesce(F.col("produksi_daging_ayam"), F.col("produksi_daging_ayam_dummy")).alias("produksi_daging"),
    F.col("konsumsi_daging_ayam").alias("konsumsi_daging"),
    F.col("permintaan_daging_ayam").alias("permintaan_daging"),
    F.col("jumlah_ternak_ayam_potong").alias("jumlah_ternak_potong"),
    F.col("harga_baseline_ayam").cast(DoubleType()).alias("harga_baseline"),
))

sdf_tr_statistik = sdf_sapi.unionByName(sdf_ayam)
sdf_tr_statistik.cache()
print(f"✅ tr_statistik (unpivot): {sdf_tr_statistik.count()} baris")
sdf_tr_statistik.show(5)


# ---
# ## LANGKAH 3 — Preprocessing Lanjutan
# 
# Tiga proses utama:
# 1. **Standardisasi nama provinsi** — nama resmi BPS sebagai standar (diterapkan di tabel iSIKHNAS)
# 2. **Harmonisasi format tanggal** — semua tanggal ke `DATE` format `YYYY-MM-DD`, ekstrak bulan & tahun
# 3. **Imputasi missing value** — median untuk harga (PIHPS), mean untuk populasi/produksi (BPS)

# In[116]:


# =========================================================
# CELL 12 · LANGKAH 3A — STANDARDISASI NAMA PROVINSI (iSIKHNAS)
# =========================================================
# iSIKHNAS menggunakan id_wilayah integer (1–38) yang sudah sesuai
# dengan ref_wilayah BPS. Kita perlu memastikan mapping-nya konsisten.

# Tabel ref_wilayah iSIKHNAS dari staging (38 provinsi)
sdf_ref_wilayah_isikhnas = sdf_ref_wilayah.select(
    F.col("id_wilayah").cast(IntegerType()),
    F.col("provinsi")
)

# Tabel standar: gunakan nama dari BPS sebagai master
# Karena urutan id_wilayah pada iSIKHNAS sama dengan BPS,
# kita cukup join on id_wilayah untuk mendapatkan nama resmi.
sdf_wilayah_master = (sdf_ref_wilayah_bps.alias("bps_ref")
    .join(sdf_ref_wilayah_isikhnas.alias("isk_ref"),
          F.col("bps_ref.id_wilayah") == F.col("isk_ref.id_wilayah"),
          how="full")
    .select(
        F.coalesce(F.col("bps_ref.id_wilayah"), F.col("isk_ref.id_wilayah")).alias("id_wilayah"),
        F.coalesce(F.col("bps_ref.provinsi"), F.col("isk_ref.provinsi")).alias("provinsi")
    )
    .orderBy("id_wilayah")
)

sdf_wilayah_master.cache()
print(f"✅ wilayah_master: {sdf_wilayah_master.count()} entri")
sdf_wilayah_master.show(40, truncate=False)


# In[117]:


# =========================================================
# CELL 13 · LANGKAH 3B — HARMONISASI FORMAT TANGGAL (iSIKHNAS)
# =========================================================
# Tanggal masuk sebagai string format MM/dd/yy atau MM/dd/yyyy.
# Target: DateType YYYY-MM-DD + kolom bulan & tahun diekstrak.

def parse_isikhnas_date(df, col_in: str, col_out: str = None):
    """Parse tanggal iSIKHNAS MM/dd/yy → DATE, tambah kolom bulan & tahun."""
    out = col_out or col_in
    return (df
        .withColumn(f"_{out}_str",
            # Coba format dua digit tahun dulu, fallback empat digit
            F.to_date(F.col(col_in), "MM/dd/yy")
        )
        .withColumn(f"_{out}_str4",
            F.to_date(F.col(col_in), "MM/dd/yyyy")
        )
        .withColumn(out,
            F.coalesce(F.col(f"_{out}_str"), F.col(f"_{out}_str4"))
        )
        .drop(f"_{out}_str", f"_{out}_str4", col_in if col_in != out else "__dummy")
        .withColumn(f"{out}_bulan", F.month(F.col(out)).cast(IntegerType()))
        .withColumn(f"{out}_tahun", F.year(F.col(out)).cast(IntegerType()))
    )

# ── Laporan Sakit ──
sdf_laporan_clean = parse_isikhnas_date(sdf_laporan, "tgl_lapor", "tgl_lapor")
sdf_laporan_clean = (sdf_laporan_clean
    .withColumn("id_wilayah", F.col("id_wilayah").cast(IntegerType()))
    .withColumn("jumlah_gejala", F.col("jumlah_gejala").cast(DoubleType()))
    .withColumn("jumlah_mati",   F.col("jumlah_mati").cast(DoubleType()))
)

# ── Mutasi ──
sdf_mutasi_clean = parse_isikhnas_date(sdf_mutasi, "tgl_mutasi", "tgl_mutasi")
sdf_mutasi_clean = (sdf_mutasi_clean
    .withColumn("id_asal",   F.col("id_asal").cast(IntegerType()))
    .withColumn("id_tujuan", F.col("id_tujuan").cast(IntegerType()))
    .withColumn("jumlah_ekor", F.col("jumlah_ekor").cast(DoubleType()))
)

# ── RPH ──
sdf_rph_clean = parse_isikhnas_date(sdf_rph, "tgl_potong", "tgl_potong")
sdf_rph_clean = (sdf_rph_clean
    .withColumn("id_wilayah", F.col("id_wilayah").cast(IntegerType()))
    .withColumn("berat_karkas", F.col("berat_karkas").cast(DoubleType()))
)

# ── Lab ──
sdf_lab_clean = parse_isikhnas_date(sdf_lab, "tgl_uji", "tgl_uji")

print("✅ Harmonisasi tanggal selesai.")
print("\nSampel laporan_sakit:")
sdf_laporan_clean.show(3, truncate=False)
print("\nSampel rph:")
sdf_rph_clean.show(3, truncate=False)


# In[118]:


# =========================================================
# CELL 14 · LANGKAH 3C — HARMONISASI TANGGAL & PROVINSI PIHPS
# =========================================================
# staging_pihps_raw: kolom 'waktu' bertipe TIMESTAMP.
# MASALAH: Nama provinsi PIHPS pakai CAPS + singkatan berbeda dari BPS.
# Contoh: "JAKARTA" → "DKI Jakarta", "NTB" → "Nusa Tenggara Barat"

# --- Mapping nama PIHPS (CAPS) → nama resmi BPS ---
pihps_ke_bps = {
    "ACEH"              : "Aceh",
    "SUMATERA UTARA"    : "Sumatera Utara",
    "SUMUT"             : "Sumatera Utara",
    "SUMATERA BARAT"    : "Sumatera Barat",
    "SUMBAR"            : "Sumatera Barat",
    "RIAU"              : "Riau",
    "KEPULAUAN RIAU"    : "Kepulauan Riau",
    "KEPRI"             : "Kepulauan Riau",
    "JAMBI"             : "Jambi",
    "SUMATERA SELATAN"  : "Sumatera Selatan",
    "SUMSEL"            : "Sumatera Selatan",
    "BANGKA BELITUNG"   : "Bangka Belitung",
    "KEPULAUAN BANGKA BELITUNG"  : "Bangka Belitung",
    "BABEL"             : "Bangka Belitung",
    "BENGKULU"          : "Bengkulu",
    "LAMPUNG"           : "Lampung",
    "JAKARTA"           : "DKI Jakarta",
    "DKI JAKARTA"       : "DKI Jakarta",
    "JAWA BARAT"        : "Jawa Barat",
    "JABAR"             : "Jawa Barat",
    "JAWA TENGAH"       : "Jawa Tengah",
    "JATENG"            : "Jawa Tengah",
    "DI YOGYAKARTA"     : "DI Yogyakarta",
    "YOGYAKARTA"        : "DI Yogyakarta",
    "DIY"               : "DI Yogyakarta",
    "JAWA TIMUR"        : "Jawa Timur",
    "JATIM"             : "Jawa Timur",
    "BANTEN"            : "Banten",
    "BALI"              : "Bali",
    "NTB"               : "Nusa Tenggara Barat",
    "NUSA TENGGARA BARAT": "Nusa Tenggara Barat",
    "NTT"               : "Nusa Tenggara Timur",
    "NUSA TENGGARA TIMUR": "Nusa Tenggara Timur",
    "KALIMANTAN BARAT"  : "Kalimantan Barat",
    "KALBAR"            : "Kalimantan Barat",
    "KALIMANTAN TENGAH" : "Kalimantan Tengah",
    "KALTENG"           : "Kalimantan Tengah",
    "KALIMANTAN SELATAN": "Kalimantan Selatan",
    "KALSEL"            : "Kalimantan Selatan",
    "KALIMANTAN TIMUR"  : "Kalimantan Timur",
    "KALTIM"            : "Kalimantan Timur",
    "KALIMANTAN UTARA"  : "Kalimantan Utara",
    "KALTARA"           : "Kalimantan Utara",
    "SULAWESI UTARA"    : "Sulawesi Utara",
    "SULUT"             : "Sulawesi Utara",
    "SULAWESI TENGAH"   : "Sulawesi Tengah",
    "SULTENG"           : "Sulawesi Tengah",
    "SULAWESI SELATAN"  : "Sulawesi Selatan",
    "SULSEL"            : "Sulawesi Selatan",
    "SULAWESI TENGGARA" : "Sulawesi Tenggara",
    "SULTRA"            : "Sulawesi Tenggara",
    "GORONTALO"         : "Gorontalo",
    "SULAWESI BARAT"    : "Sulawesi Barat",
    "SULBAR"            : "Sulawesi Barat",
    "MALUKU"            : "Maluku",
    "MALUKU UTARA"      : "Maluku Utara",
    "PAPUA"             : "Papua",
    "PAPUA BARAT"       : "Papua Barat",
    "PAPUA SELATAN"     : "Papua Selatan",
    "PAPUA TENGAH"      : "Papua Tengah",
    "PAPUA PEGUNUNGAN"  : "Papua Pegunungan",
    "PAPUA BARAT DAYA"  : "Papua Barat Daya",
}

# Buat mapping expression PySpark
map_expr = F.create_map([F.lit(x) for pair in pihps_ke_bps.items() for x in pair])

sdf_pihps_clean = (sdf_pihps
    .withColumn("waktu",  F.col("waktu").cast(TimestampType()))
    .withColumn("tgl",    F.to_date(F.col("waktu")))
    .withColumn("bulan",  F.month(F.col("waktu")).cast(IntegerType()))
    .withColumn("tahun",  F.year(F.col("waktu")).cast(IntegerType()))
    .withColumn("harga",  F.col("harga").cast(DoubleType()))
    # Standardisasi nama komoditas
    .withColumn("nama_komoditas",
        F.when(F.lower(F.col("nama_komoditas")).contains("sapi"), F.lit("Sapi"))
         .when(F.lower(F.col("nama_komoditas")).contains("ayam"), F.lit("Ayam"))
         .otherwise(F.col("nama_komoditas"))
    )
    # Konversi nama PIHPS → nama resmi BPS via mapping dictionary
    # Trim + upper dulu agar konsisten, lalu lookup map
    .withColumn("provinsi",
        F.coalesce(
            map_expr[F.upper(F.trim(F.col("provinsi")))],
            F.col("provinsi")   # fallback: pakai nama asli jika tidak ada di map
        )
    )
)

sdf_pihps_clean.cache()
print(f"✅ PIHPS clean: {sdf_pihps_clean.count()} baris")

# --- Verifikasi: tampilkan provinsi unik setelah mapping ---
print("\nProvinsi unik di PIHPS setelah mapping:")
sdf_pihps_clean.select("provinsi").distinct().orderBy("provinsi").show(50, truncate=False)
sdf_pihps_clean.printSchema()
sdf_pihps_clean.show(5, truncate=False)


# In[119]:


# =========================================================
# CELL 15 · LANGKAH 3D — IMPUTASI MISSING VALUE
# =========================================================

# ── A. PIHPS: Imputasi harga dengan MEDIAN per komoditas-provinsi-bulan ──
# Hitung median per grup
sdf_pihps_median = (sdf_pihps_clean
    .groupBy("provinsi", "nama_komoditas", "bulan")
    .agg(F.percentile_approx("harga", 0.5).alias("median_harga"))
)

sdf_pihps_imputed = (sdf_pihps_clean.alias("p")
    .join(sdf_pihps_median.alias("m"),
          on=["provinsi", "nama_komoditas", "bulan"],
          how="left")
    .withColumn("harga",
        F.when(F.col("p.harga").isNull(), F.col("m.median_harga"))
         .otherwise(F.col("p.harga"))
    )
    .drop("median_harga")
)

# ── B. BPS tr_statistik: Imputasi populasi & produksi dengan MEAN per wilayah-komoditas ──
sdf_tr_stat_mean = (sdf_tr_statistik
    .groupBy("id_wilayah", "id_komoditas")
    .agg(
        F.mean("populasi").alias("mean_populasi"),
        F.mean("produksi_daging").alias("mean_produksi"),
        F.mean("konsumsi_daging").alias("mean_konsumsi"),
        F.mean("permintaan_daging").alias("mean_permintaan"),
        F.mean("jumlah_ternak_potong").alias("mean_ternak_potong"),
    )
)

sdf_tr_statistik_imputed = (sdf_tr_statistik.alias("s")
    .join(sdf_tr_stat_mean.alias("m"),
          on=["id_wilayah", "id_komoditas"],
          how="left")
    .withColumn("populasi",        F.coalesce(F.col("s.populasi"),        F.col("m.mean_populasi")))
    .withColumn("produksi_daging", F.coalesce(F.col("s.produksi_daging"), F.col("m.mean_produksi")))
    .withColumn("konsumsi_daging", F.coalesce(F.col("s.konsumsi_daging"), F.col("m.mean_konsumsi")))
    .withColumn("permintaan_daging",   F.coalesce(F.col("s.permintaan_daging"),   F.col("m.mean_permintaan")))
    .withColumn("jumlah_ternak_potong",F.coalesce(F.col("s.jumlah_ternak_potong"),F.col("m.mean_ternak_potong")))
    .select("s.id_wilayah","s.tahun","s.id_komoditas",
            "populasi","produksi_daging","konsumsi_daging",
            "permintaan_daging","jumlah_ternak_potong","s.harga_baseline")
)

sdf_tr_statistik_imputed.cache()
print("✅ Imputasi selesai.")
print(f"   PIHPS missing setelah imputasi : {sdf_pihps_imputed.filter(F.col('harga').isNull()).count()}")
print(f"   tr_statistik missing populasi  : {sdf_tr_statistik_imputed.filter(F.col('populasi').isNull()).count()}")


# ---
# ## LANGKAH 4 — Membangun Tabel Dimensi (Surrogate Key & DDL Constraint)
# 
# Tiga tabel dimensi dibentuk:
# - `dim_prov` — provinsi dengan surrogate key & kode BPS
# - `dim_komoditas` — Sapi / Ayam
# - `dim_waktu` — deret waktu otomatis (bulan, kuartal, tahun)

# In[120]:


# =========================================================
# CELL 16 · LANGKAH 4A — dim_prov (FIX FINAL)
# =========================================================

from pyspark.sql.window import Window

window_dim_prov = Window.orderBy("provinsi")

sdf_dim_prov = (sdf_wilayah_master
    .select("provinsi")
    .dropDuplicates()
    .orderBy("provinsi")
    .withColumn("prov_key", F.row_number().over(window_dim_prov))  # surrogate key
    .withColumn("id_prov", F.col("prov_key"))  # natural key = urutan bersih
    .select(
        "prov_key",
        "id_prov",
        F.col("provinsi").alias("nama_provinsi")
    )
)

sdf_dim_prov.cache()
print(f"✅ dim_prov (FIXED): {sdf_dim_prov.count()} baris")
sdf_dim_prov.show(40, truncate=False)


# In[121]:


# =========================================================
# CELL 17 · LANGKAH 4B — dim_komoditas
# =========================================================
from pyspark.sql.types import StructType, StructField, IntegerType as IT, StringType as ST

schema_kom = StructType([
    StructField("komoditas_key",  IT(), False),
    StructField("id_komoditas",   IT(), False),
    StructField("nama_komoditas", ST(), True),
])
sdf_dim_komoditas = spark.createDataFrame(
    [
        (1, 1, "Sapi"),
        (2, 2, "Ayam")
    ],
    ["komoditas_key", "id_komoditas", "nama_komoditas"]
)
print("✅ dim_komoditas:")
sdf_dim_komoditas.show()


# In[122]:


# =========================================================
# CELL 18 · LANGKAH 4C — dim_waktu
# =========================================================
# FIX: hardcode 2020-2025 agar tidak ikut tahun kotor dari iSIKHNAS

tahun_min = 2020
tahun_max = 2025
print(f"   Rentang tahun: {tahun_min} — {tahun_max} (hardcoded sesuai dokumen)")

import itertools
waktu_rows = [
    (y, m) for y in range(tahun_min, tahun_max + 1) for m in range(1, 13)
]

sdf_waktu_base = spark.createDataFrame(waktu_rows, ["tahun", "bulan"])

nama_bulan_map = {
    1:"Januari", 2:"Februari", 3:"Maret", 4:"April",
    5:"Mei", 6:"Juni", 7:"Juli", 8:"Agustus",
    9:"September", 10:"Oktober", 11:"November", 12:"Desember"
}
nama_bulan_expr = F.create_map([F.lit(x) for pair in nama_bulan_map.items() for x in pair])

window_waktu = Window.orderBy("tahun", "bulan")

sdf_dim_waktu = (sdf_waktu_base
    .withColumn("waktu_key", F.row_number().over(window_waktu))
    .withColumn("nama_bulan", nama_bulan_expr[F.col("bulan")])
    .withColumn("kuartal",
        F.when(F.col("bulan").between(1,3), F.lit(1))
         .when(F.col("bulan").between(4,6), F.lit(2))
         .when(F.col("bulan").between(7,9), F.lit(3))
         .otherwise(F.lit(4))
         .cast(IntegerType())
    )
    .select("waktu_key", "bulan", "nama_bulan", "kuartal", "tahun")
)

sdf_dim_waktu.cache()
print(f"✅ dim_waktu: {sdf_dim_waktu.count()} baris (harusnya 72)")
sdf_dim_waktu.show(100)


# ---
# ## LANGKAH 5A — Agregasi iSIKHNAS & PIHPS
# 
# Agregasi metrik operasional `GROUP BY (prov_key, waktu_key, komoditas_key)` menghasilkan:
# - **Metrik iSIKHNAS**: sum_jumlah_sakit, sum_jumlah_mati, sum_vol_mutasi, sum_realisasi_karkas
# - **Metrik PIHPS**: avg_harga

# In[123]:


# =========================================================
# CELL 19 · LANGKAH 5A-i — AGREGASI iSIKHNAS (Laporan Sakit)
# =========================================================

# Join laporan_sakit ← hewan (untuk id_komoditas)
sdf_laporan_joined = (sdf_laporan_clean.alias("lap")
    .join(sdf_ref_hewan.alias("hw"),
          F.col("lap.id_hewan") == F.col("hw.id_hewan"),
          how="left")
    # Map nama hewan → id_komoditas (Sapi=1, Ayam=2)
    .withColumn("id_komoditas",
        F.when(F.lower(F.col("hw.nama_hewan")) == "sapi", F.lit(1))
         .when(F.lower(F.col("hw.nama_hewan")) == "ayam", F.lit(2))
         .otherwise(F.lit(0))
    )
    .withColumn("id_wilayah", F.col("lap.id_wilayah").cast(IntegerType()))
)

# Agregasi: SUM per wilayah-bulan-komoditas
sdf_agg_sakit = (sdf_laporan_joined
    .groupBy(
        "id_wilayah",
        F.col("tgl_lapor_bulan").alias("bulan"),
        F.col("tgl_lapor_tahun").alias("tahun"),
        "id_komoditas"
    )
    .agg(
        F.sum("jumlah_gejala").alias("sum_jumlah_sakit"),
        F.sum("jumlah_mati").alias("sum_jumlah_mati")
    )
)

print(f"✅ Agregasi laporan_sakit: {sdf_agg_sakit.count()} baris")
sdf_agg_sakit.show(5)


# In[124]:


# =========================================================
# CELL 20 · LANGKAH 5A-ii — AGREGASI iSIKHNAS (Mutasi & RPH)
# =========================================================

# ── Mutasi: vol mutasi keluar dari provinsi asal ──
sdf_mutasi_joined = (sdf_mutasi_clean.alias("mut")
    .join(sdf_ref_hewan.alias("hw"),
          F.col("mut.id_hewan") == F.col("hw.id_hewan"), how="left")
    .withColumn("id_komoditas",
        F.when(F.lower(F.col("hw.nama_hewan")) == "sapi", F.lit(1))
         .when(F.lower(F.col("hw.nama_hewan")) == "ayam", F.lit(2))
         .otherwise(F.lit(0))
    )
)

sdf_agg_mutasi = (sdf_mutasi_joined
    .groupBy(
        F.col("id_asal").alias("id_wilayah"),
        F.col("tgl_mutasi_bulan").alias("bulan"),
        F.col("tgl_mutasi_tahun").alias("tahun"),
        "id_komoditas"
    )
    .agg(F.sum("jumlah_ekor").alias("sum_vol_mutasi"))
)

# ── RPH: total berat karkas ──
sdf_rph_joined = (sdf_rph_clean.alias("rph")
    .join(sdf_ref_hewan.alias("hw"),
          F.col("rph.id_hewan") == F.col("hw.id_hewan"), how="left")
    .withColumn("id_komoditas",
        F.when(F.lower(F.col("hw.nama_hewan")) == "sapi", F.lit(1))
         .when(F.lower(F.col("hw.nama_hewan")) == "ayam", F.lit(2))
         .otherwise(F.lit(0))
    )
)

sdf_agg_rph = (sdf_rph_joined
    .groupBy(
        F.col("rph.id_wilayah"),
        F.col("tgl_potong_bulan").alias("bulan"),
        F.col("tgl_potong_tahun").alias("tahun"),
        "id_komoditas"
    )
    .agg(F.sum("berat_karkas").alias("sum_realisasi_karkas"))
)

print(f"✅ Agregasi mutasi : {sdf_agg_mutasi.count()} baris")
print(f"✅ Agregasi RPH    : {sdf_agg_rph.count()} baris")


# In[125]:


# =========================================================
# CELL 21 · LANGKAH 5A-iii — AGREGASI PIHPS (Rata-rata Harga)
# =========================================================

# Join PIHPS dengan dim_prov — pakai lower+trim di kedua sisi
# agar tahan perbedaan kapitalisasi yang mungkin masih tersisa
sdf_pihps_prov = (sdf_pihps_imputed.alias("p")
    .join(
        sdf_dim_prov.alias("dp"),
        F.lower(F.trim(F.col("p.provinsi"))) == F.lower(F.trim(F.col("dp.nama_provinsi"))),
        how="left"
    )
    .withColumn("id_komoditas",
        F.when(F.col("p.nama_komoditas") == "Sapi", F.lit(1))
         .when(F.col("p.nama_komoditas") == "Ayam", F.lit(2))
         .otherwise(F.lit(0))
    )
)

# --- Debug: cek jika masih ada yang tidak match ---
tidak_match = sdf_pihps_prov.filter(F.col("dp.id_prov").isNull()) \
    .select("p.provinsi").distinct()

n_tidak_match = tidak_match.count()
if n_tidak_match > 0:
    print(f"⚠️  {n_tidak_match} provinsi PIHPS masih tidak match ke dim_prov:")
    tidak_match.show(truncate=False)
else:
    print("✅ Semua provinsi PIHPS berhasil match ke dim_prov.")

# Agregasi avg_harga — filter id_prov null sebelum groupBy
sdf_agg_harga = (sdf_pihps_prov
    .filter(F.col("dp.id_prov").isNotNull())
    .groupBy(
        F.col("dp.id_prov"),
        F.col("p.bulan"),
        F.col("p.tahun"),
        "id_komoditas"
    )
    .agg(F.avg("harga").alias("avg_harga"))
    .withColumnRenamed("id_prov", "id_wilayah") # Kembalikan nama ke id_wilayah untuk JOIN di Cell 22
)

print(f"\n✅ Agregasi PIHPS harga: {sdf_agg_harga.count()} baris")
print(f"   Null id_wilayah: {sdf_agg_harga.filter(F.col('id_wilayah').isNull()).count()}")
sdf_agg_harga.show(5)


# In[126]:


# =========================================================
# CELL 22 · LANGKAH 5A-iv — GABUNG SEMUA AGREGASI iSIKHNAS + PIHPS
# =========================================================
# Full outer join sehingga tidak ada data yang hilang.

sdf_agg_isikhnas = (sdf_agg_sakit.alias("sk")
    .join(sdf_agg_mutasi.alias("mut"),
          on=["id_wilayah","bulan","tahun","id_komoditas"], how="full")
    .join(sdf_agg_rph.alias("rph"),
          on=["id_wilayah","bulan","tahun","id_komoditas"], how="full")
    .select(
        F.coalesce(F.col("sk.id_wilayah"),F.col("mut.id_wilayah"),F.col("rph.id_wilayah")).alias("id_wilayah"),
        F.coalesce(F.col("sk.bulan"),F.col("mut.bulan"),F.col("rph.bulan")).alias("bulan"),
        F.coalesce(F.col("sk.tahun"),F.col("mut.tahun"),F.col("rph.tahun")).alias("tahun"),
        F.coalesce(F.col("sk.id_komoditas"),F.col("mut.id_komoditas"),F.col("rph.id_komoditas")).alias("id_komoditas"),
        F.col("sk.sum_jumlah_sakit"),
        F.col("sk.sum_jumlah_mati"),
        F.col("mut.sum_vol_mutasi"),
        F.col("rph.sum_realisasi_karkas"),
    )
)

# Gabung dengan PIHPS
sdf_agg_all = (sdf_agg_isikhnas.alias("isk")
    .join(sdf_agg_harga.alias("ph"),
          on=["id_wilayah","bulan","tahun","id_komoditas"], how="full")
    .select(
        F.coalesce(F.col("isk.id_wilayah"),F.col("ph.id_wilayah")).alias("id_wilayah"),
        F.coalesce(F.col("isk.bulan"),F.col("ph.bulan")).alias("bulan"),
        F.coalesce(F.col("isk.tahun"),F.col("ph.tahun")).alias("tahun"),
        F.coalesce(F.col("isk.id_komoditas"),F.col("ph.id_komoditas")).alias("id_komoditas"),
        F.col("isk.sum_jumlah_sakit"),
        F.col("isk.sum_jumlah_mati"),
        F.col("isk.sum_vol_mutasi"),
        F.col("isk.sum_realisasi_karkas"),
        F.col("ph.avg_harga"),
    )
    .filter(F.col("id_komoditas").isin([1, 2]))   # Hanya Sapi & Ayam
)

sdf_agg_all.cache()
print(f"✅ Total agregasi gabungan: {sdf_agg_all.count()} baris")
sdf_agg_all.show(5)


# ---
# ## LANGKAH 5B — Normalisasi & Konversi Data BPS
# 
# - **Konversi satuan**: produksi daging sapi (ton → kg × 1000)
# - **Normalisasi waktu** (bagi 12 → metrik bulanan): avg_produksi, avg_konsumsi, avg_permintaan, avg_pemotongan

# In[127]:


# =========================================================
# CELL 23 · LANGKAH 5B — NORMALISASI & KONVERSI BPS
# =========================================================
# JOIN dengan tr_demografi untuk mendapatkan jumlah_penduduk
# agar avg_konsumsi_bulanan bisa dihitung dengan benar.

sdf_bps_dengan_penduduk = (sdf_tr_statistik_imputed.alias("st")
    .join(
        sdf_tr_demografi.alias("dem"),
        on=["id_wilayah", "tahun"],
        how="left"
    )
)

sdf_bps_bulanan = (sdf_bps_dengan_penduduk
    .withColumn("populasi_ternak", F.col("populasi"))
    .withColumn("produksi_daging_kg",
        F.when(F.col("id_komoditas") == 1,
               F.col("produksi_daging") * F.lit(1000.0))
         .otherwise(F.col("produksi_daging"))
    )
    .withColumn("avg_produksi_bulanan",
        F.col("produksi_daging_kg") / F.lit(12.0))
    .withColumn("avg_konsumsi_bulanan",
        F.when(
            F.col("dem.jumlah_penduduk").isNull() | (F.col("dem.jumlah_penduduk") <= 0),
            F.col("konsumsi_daging") / F.lit(12.0)
        ).otherwise(
            F.col("konsumsi_daging") * F.col("dem.jumlah_penduduk") / F.lit(12.0)
        )
    )
    .withColumn("avg_permintaan_bulanan",
        F.col("permintaan_daging") / F.lit(12.0))
    .withColumn("avg_pemotongan_bulanan",
        F.col("jumlah_ternak_potong") / F.lit(12.0))
    .select(
        "st.id_wilayah", "st.tahun", "st.id_komoditas",
        "populasi_ternak", "st.harga_baseline",
        "avg_produksi_bulanan", "avg_konsumsi_bulanan",
        "avg_permintaan_bulanan", "avg_pemotongan_bulanan",
        "dem.jumlah_penduduk",   # ← FIX: bawa ke fact
        "dem.growth_populasi",   # ← FIX: bawa ke fact
    )
)

sdf_bps_bulanan.cache()
print(f"✅ BPS bulanan: {sdf_bps_bulanan.count()} baris")
sdf_bps_bulanan.show(5)


# In[ ]:





# ---
# ## LANGKAH 5C — Integrasi (INNER JOIN Agregasi + BPS)
# 
# Join antara agregasi operasional (per bulan) dengan data BPS (per tahun).
# Karena BPS granularitasnya tahunan, nilainya akan terduplikasi di setiap bulan dalam tahun yang sama — ini perilaku yang diharapkan.

# In[128]:


# =========================================================
# CELL 24 · LANGKAH 5C — INNER JOIN AGREGASI + BPS
# =========================================================
# Join agregasi operasional (per bulan) dengan data BPS (per tahun).
# Karena BPS granularitas tahunan, nilai BPS terduplikasi per bulan
# dalam tahun yang sama — ini perilaku yang BENAR.

sdf_integrated = (sdf_agg_all.alias("agg")
    .join(sdf_bps_bulanan.alias("bps"),
          on=[
              F.col("agg.id_wilayah")   == F.col("bps.id_wilayah"),
              F.col("agg.id_komoditas") == F.col("bps.id_komoditas"),
              F.col("agg.tahun")        == F.col("bps.tahun"),
          ],
          how="inner"
    )
    .select(
        F.col("agg.id_wilayah"),
        F.col("agg.bulan"),
        F.col("agg.tahun"),
        F.col("agg.id_komoditas"),
        # Metrik iSIKHNAS — null diganti 0 karena memang tidak ada kejadian
        F.coalesce(F.col("agg.sum_jumlah_sakit"),    F.lit(0.0)).alias("sum_jumlah_sakit"),
        F.coalesce(F.col("agg.sum_jumlah_mati"),     F.lit(0.0)).alias("sum_jumlah_mati"),
        F.coalesce(F.col("agg.sum_vol_mutasi"),      F.lit(0.0)).alias("sum_vol_mutasi"),
        F.coalesce(F.col("agg.sum_realisasi_karkas"),F.lit(0.0)).alias("sum_realisasi_karkas"),
        # Metrik PIHPS — avg_harga bisa null, akan diimputasi di Cell 25
        F.col("agg.avg_harga"),
        # Metrik BPS — terduplikasi per bulan dalam tahun yang sama (OK)
        F.col("bps.jumlah_penduduk"),    # dari tr_demografi via join di Cell 23
        F.col("bps.growth_populasi"),    # dari tr_demografi via join di Cell 23
        F.col("bps.populasi_ternak"),
        F.col("bps.harga_baseline"),
        F.col("bps.avg_produksi_bulanan"),
        F.col("bps.avg_konsumsi_bulanan"),
        F.col("bps.avg_permintaan_bulanan"),
        F.col("bps.avg_pemotongan_bulanan"),
    )
)

sdf_integrated.cache()
print(f"✅ Data terintegrasi: {sdf_integrated.count()} baris")
print(f"   Null avg_harga   : {sdf_integrated.filter(F.col('avg_harga').isNull()).count()} baris")
sdf_integrated.show(5)


# ---
# ## LANGKAH 5D — Menghitung `supply_risk_index`
# 
# Indeks risiko dihitung dari tiga komponen:
# 
# | Komponen | Formula | Bobot |
# |---|---|---|
# | **Price Gap** | `(avg_harga − harga_baseline) / harga_baseline` | 1/3 |
# | **Health Impact** | `(sum_jumlah_sakit + sum_jumlah_mati) / populasi_ternak` | 1/3 |
# | **Supply Strain** | `sum_vol_mutasi / avg_permintaan_bulanan` | 1/3 |
# 
# Setiap komponen di-**min-max scaling** ke `[0.0, 1.0]` menggunakan `greatest`/`least` di PySpark sebelum dirata-rata.

# In[129]:


# =========================================================
# CELL 25 · LANGKAH 5D-i — IMPUTASI avg_harga YANG KOSONG
# =========================================================
# Strategi 3 lapis:
# 1. avg_harga asli dari PIHPS
# 2. Fallback 1: last non-null dalam partisi (Window)
# 3. Fallback 2: median global per komoditas (safety net)

sdf_global_median = (sdf_integrated
    .filter(F.col("avg_harga").isNotNull())
    .groupBy("id_komoditas")
    .agg(F.percentile_approx("avg_harga", 0.5).alias("global_median_harga"))
)

window_median_fallback = Window.partitionBy("id_wilayah","id_komoditas").orderBy("tahun","bulan")

sdf_with_prev_median = (sdf_integrated
    .join(sdf_global_median, on="id_komoditas", how="left")
    .withColumn("prev_harga_median",
        F.last(F.col("avg_harga"), ignorenulls=True)
         .over(window_median_fallback.rowsBetween(Window.unboundedPreceding, -1))
    )
    .withColumn("avg_harga",
        F.when(F.col("avg_harga").isNotNull(),         F.col("avg_harga"))
         .when(F.col("prev_harga_median").isNotNull(),  F.col("prev_harga_median"))
         .otherwise(F.col("global_median_harga"))
    )
    .drop("prev_harga_median", "global_median_harga")
)

null_sebelum = sdf_integrated.filter(F.col("avg_harga").isNull()).count()
null_sesudah = sdf_with_prev_median.filter(F.col("avg_harga").isNull()).count()
print(f"✅ Imputasi avg_harga selesai.")
print(f"   Null sebelum : {null_sebelum}")
print(f"   Null sesudah : {null_sesudah}")
sdf_with_prev_median.select("id_wilayah","bulan","tahun","id_komoditas","avg_harga").show(10)


# In[130]:


# =========================================================
# CELL 26 · LANGKAH 5D-ii — HITUNG KOMPONEN INDEKS (RAW)
# =========================================================
# Guard division by zero: jika pembagi = 0 atau null → komponen = 0.

EPS = 1e-9   # epsilon kecil untuk hindari div/0

sdf_components = (sdf_with_prev_median
    # ── Price Gap ──────────────────────────────────────────────────────────
    .withColumn("raw_price_gap",
        F.when(
            (F.col("harga_baseline").isNull()) | (F.col("harga_baseline") <= 0) |
            (F.col("avg_harga").isNull()),
            F.lit(0.0)
        ).otherwise(
            (F.col("avg_harga") - F.col("harga_baseline")) / (F.col("harga_baseline") + F.lit(EPS))
        )
    )
    # ── Health Impact ───────────────────────────────────────────────────────
    .withColumn("raw_health_impact",
        F.when(
            (F.col("populasi_ternak").isNull()) | (F.col("populasi_ternak") <= 0),
            F.lit(0.0)
        ).otherwise(
            (F.col("sum_jumlah_sakit") + F.col("sum_jumlah_mati")) /
            (F.col("populasi_ternak") + F.lit(EPS))
        )
    )
    # ── Supply Strain ───────────────────────────────────────────────────────
    .withColumn("raw_supply_strain",
        F.when(
            (F.col("avg_permintaan_bulanan").isNull()) | (F.col("avg_permintaan_bulanan") <= 0),
            F.lit(0.0)
        ).otherwise(
            F.col("sum_vol_mutasi") / (F.col("avg_permintaan_bulanan") + F.lit(EPS))
        )
    )
)

print("✅ Komponen raw dihitung.")
sdf_components.select("id_wilayah","bulan","tahun","id_komoditas",
                       "raw_price_gap","raw_health_impact","raw_supply_strain").show(5)


# In[131]:


# =========================================================
# CELL 27 · LANGKAH 5D-iii — MIN-MAX SCALING PER KOMPONEN
# =========================================================
# Scaling global: min & max dihitung dari seluruh dataset
# lalu dibroadcast. Menggunakan greatest/least untuk clamp ke [0,1].

def minmax_scale(df, col_raw: str, col_scaled: str):
    """Min-max scaling global, hasil di-clamp ke [0.0, 1.0]."""
    stats = df.agg(
        F.min(col_raw).alias("_min"),
        F.max(col_raw).alias("_max")
    ).collect()[0]
    v_min, v_max = float(stats["_min"] or 0), float(stats["_max"] or 1)
    denom = v_max - v_min if (v_max - v_min) != 0 else 1.0
    return (df
        .withColumn(col_scaled,
            F.greatest(
                F.lit(0.0),
                F.least(
                    F.lit(1.0),
                    (F.col(col_raw) - F.lit(v_min)) / F.lit(denom)
                )
            )
        )
    )

sdf_scaled = sdf_components
sdf_scaled = minmax_scale(sdf_scaled, "raw_price_gap",      "scaled_price_gap")
sdf_scaled = minmax_scale(sdf_scaled, "raw_health_impact",  "scaled_health_impact")
sdf_scaled = minmax_scale(sdf_scaled, "raw_supply_strain",  "scaled_supply_strain")

print("✅ Min-max scaling selesai.")
sdf_scaled.select("id_wilayah","bulan","tahun","id_komoditas",
                  "scaled_price_gap","scaled_health_impact","scaled_supply_strain").show(5)


# In[132]:


# =========================================================
# CELL 28 · LANGKAH 5D-iv — HITUNG supply_risk_index
# =========================================================
# Rata-rata sederhana 3 komponen (bobot sama 1/3 masing-masing)

sdf_with_index = (sdf_scaled
    .withColumn("supply_risk_index",
        F.round(
            (F.col("scaled_price_gap") +
             F.col("scaled_health_impact") +
             F.col("scaled_supply_strain")) / F.lit(3.0),
            6
        )
    )
)

print("✅ supply_risk_index dihitung.")
sdf_with_index.select("id_wilayah","bulan","tahun","id_komoditas","supply_risk_index").show(10)


# ---
# ## Output — Tabel Fakta: `fact_supply_resilience`
# 
# Gabungkan semua surrogate key dari tabel dimensi ke dalam tabel fakta final.

# In[133]:


# =========================================================
# CELL 29 · BANGUN fact_supply_resilience (INJEKSI SURROGATE KEY)
# =========================================================

sdf_fact_raw = (sdf_with_index.alias("f")
    .join(sdf_dim_prov.alias("dp"),
          F.col("f.id_wilayah") == F.col("dp.id_prov"), how="left")
    .join(sdf_dim_komoditas.alias("dk"),
          F.col("f.id_komoditas") == F.col("dk.id_komoditas"), how="left")
    .join(sdf_dim_waktu.alias("dw"),
          (F.col("f.bulan") == F.col("dw.bulan")) &
          (F.col("f.tahun") == F.col("dw.tahun")),
          how="left")
    .select(
        F.col("dp.prov_key"),
        F.col("dw.waktu_key"),
        F.col("dk.komoditas_key"),
        F.col("f.sum_jumlah_sakit"),
        F.col("f.sum_jumlah_mati"),
        F.col("f.sum_vol_mutasi"),
        F.col("f.sum_realisasi_karkas"),
        F.round(F.col("f.avg_harga"), 2).alias("avg_harga"),
        F.round(F.col("f.harga_baseline"), 2).alias("harga_baseline"),
        F.round(F.col("f.populasi_ternak"), 0).alias("populasi_ternak"),
        F.round(F.col("f.avg_produksi_bulanan"), 2).alias("avg_produksi"),
        F.round(F.col("f.avg_konsumsi_bulanan"), 2).alias("avg_konsumsi"),
        F.round(F.col("f.avg_pemotongan_bulanan"), 2).alias("avg_pemotongan"),
        F.round(F.col("f.avg_permintaan_bulanan"), 2).alias("avg_permintaan"),
        # FIX: tambah dua kolom ini
        F.col("f.jumlah_penduduk").cast(LongType()).alias("jumlah_penduduk"),
        F.col("f.growth_populasi"),
        F.col("f.supply_risk_index"),
    )
    .filter(F.col("prov_key").isNotNull() & F.col("waktu_key").isNotNull())
)

sdf_fact_supply_resilience = sdf_fact_raw
sdf_fact_supply_resilience.cache()

total_rows = sdf_fact_supply_resilience.count()
print(f"✅ fact_supply_resilience siap: {total_rows} baris × {len(sdf_fact_supply_resilience.columns)} kolom")
sdf_fact_supply_resilience.printSchema()
sdf_fact_supply_resilience.show(10)


# ---
# ## Validasi Hasil Transform
# 
# Cek distribusi, missing values, dan rentang indeks risiko sebelum dikirim ke tahap Load.

# In[134]:



# In[135]:


# =========================================================
# CELL 31 · SIMPAN OUTPUT TRANSFORM (PARQUET ONLY)
# =========================================================
import os

OUTPUT_DIR = "../../DATA/TRANSFORM_OUTPUT"
os.makedirs(OUTPUT_DIR, exist_ok=True)

tables_to_save = {
    "dim_prov":                sdf_dim_prov,
    "dim_komoditas":           sdf_dim_komoditas,
    "dim_waktu":               sdf_dim_waktu,
    "ref_wilayah_master":      sdf_wilayah_master,
    "ref_komoditas":           sdf_ref_komoditas,
    "tr_demografi":            sdf_tr_demografi,
    "tr_statistik":            sdf_tr_statistik_imputed,
    "fact_supply_resilience":  sdf_fact_supply_resilience,
}

print("💾 Menyimpan ke Parquet (overwrite)...\n")

for name, df in tables_to_save.items():
    path = os.path.join(OUTPUT_DIR, name)

    # Opsional: kurangi jumlah file part (biar rapi untuk demo)
    # Atur angka sesuai kebutuhan (misal 1–4)
    df_to_write = df.coalesce(1)

    (df_to_write.write
        .mode("overwrite")
        .option("compression", "snappy")
        .parquet(path)
    )
    print(f"  ✅ {name:<30} → {path}")
# Bebaskan cache yang tidak dipakai lagi sebelum write Parquet
sdf_bps_master.unpersist()
sdf_tr_statistik.unpersist()
sdf_agg_all.unpersist()
sdf_tr_statistik_imputed.unpersist()
sdf_bps_bulanan.unpersist()
sdf_integrated.unpersist()
print("✅ Cache lama dibebaskan, siap simpan Parquet.")
print("\n✅ Semua output transform tersimpan (PARQUET ONLY).")
print(f"   Folder : {os.path.abspath(OUTPUT_DIR)}")


# ---
# ## Ringkasan Fase Transform
# 
# | Langkah | Proses | Output |
# |---|---|---|
# | **1** | Cleaning & Merge BPS (API + Dummy) | `sdf_bps_master` |
# | **2** | Normalisasi & Unpivot BPS | `ref_wilayah`, `ref_komoditas`, `tr_demografi`, `tr_statistik` |
# | **3** | Standardisasi provinsi, Harmonisasi tanggal, Imputasi | Data bersih per sumber |
# | **4** | Bangun dimensi (surrogate key) | `dim_prov`, `dim_komoditas`, `dim_waktu` |
# | **5A** | Agregasi iSIKHNAS & PIHPS per (wilayah, bulan, komoditas) | Metrik operasional |
# | **5B** | Konversi satuan & normalisasi waktu BPS | Metrik bulanan BPS |
# | **5C** | Integrasi INNER JOIN agregasi + BPS | Dataset terintegrasi |
# | **5D** | Hitung `supply_risk_index` (Price Gap + Health Impact + Supply Strain) | `fact_supply_resilience` |
# 
# **Tabel siap Load ke Data Warehouse:**
# - `dim_prov` (38 baris)
# - `dim_komoditas` (2 baris)
# - `dim_waktu` (deret bulan otomatis)
# - `fact_supply_resilience` (tabel fakta utama)
# 
# > **Next step → Fase 3: LOAD** — Load semua tabel di atas ke PostgreSQL `datawarehouse_db` menggunakan PySpark JDBC writer.
# 
