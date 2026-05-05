#!/usr/bin/env python
# coding: utf-8

# # ETL Pipeline: Livestock Intelligence - FASE 2 (TRANSFORM)

import os
os.environ["PYSPARK_PYTHON"] = r"C:\Users\anggi\AppData\Local\Programs\Python\Python310\python.exe"
os.environ["PYSPARK_DRIVER_PYTHON"] = r"C:\Users\anggi\AppData\Local\Programs\Python\Python310\python.exe"
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
PG_PASS     = 'mydatabase'
PG_HOST     = 'localhost'
PG_PORT     = '5432'
STAGING_DB  = 'staging_db'

PG_JDBC_URL  = f"jdbc:postgresql://{PG_HOST}:{PG_PORT}/{STAGING_DB}"
PG_JDBC_PROPS = {
    "user":     PG_USER,
    "password": PG_PASS,
    "driver":   "org.postgresql.Driver"
}

# --- INISIALISASI SPARK SESSION ---

JDBC_JAR = "C:/Users/anggi/Documents/KULIAH/TINGKAT 3/SEMESTER 6/TPD/PROJECT UTS/UTS-TPD-KELOMPOK-1/postgresql-42.7.11.jar"

try:
    spark.stop()
except:
    pass

spark = (SparkSession.builder
    .appName("Livestock Intelligence - Transform")
    .config("spark.jars", JDBC_JAR)
    .config("spark.driver.extraClassPath", JDBC_JAR)
    .config("spark.executor.extraClassPath", JDBC_JAR)
    .config("spark.sql.legacy.timeParserPolicy", "LEGACY")
    .config("spark.driver.memory", "6g")
    .config("spark.driver.maxResultSize", "2g")        # ← tambah
    .config("spark.sql.shuffle.partitions", "4")       # ← tambah
    .config("spark.network.timeout", "800s")
    .config("spark.executor.heartbeatInterval", "120s")
    .config("spark.driver.host", "127.0.0.1")
    .config("spark.driver.bindAddress", "127.0.0.1")
    .config("spark.python.worker.reuse", "false")
    .config("spark.hadoop.fs.file.impl", "org.apache.hadoop.fs.LocalFileSystem")
    .config("spark.hadoop.io.native.lib.available", "false")    
    .config("spark.hadoop.fs.file.impl", "org.apache.hadoop.fs.RawLocalFileSystem")
    .config("spark.hadoop.fs.file.impl.disable.cache", "true")
    .getOrCreate())

spark.sparkContext.setLogLevel("WARN")
print("[SUCCESS] SparkSession berhasil diinisialisasi.")
print(f"   Spark version : {spark.version}")
print(f"   JDBC URL      : {PG_JDBC_URL}")

print(spark.sparkContext._conf.get("spark.jars"))

# --- HELPER FUNCTIONS ---

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
    print(f"   {table_name:<45} -> {df.count():>6} baris, {len(df.columns)} kolom")
    return df

def show_info(df, label: str, n: int = 5):
    """Menampilkan info singkat dataframe."""
    print(f"\n{'='*60}")
    print(f"  {label}  |  {df.count()} baris X {len(df.columns)} kolom")
    print(f"{'='*60}")
    df.printSchema()
    df.show(n, truncate=False)

print("[SUCCESS] Helper functions siap.")

# --- LOAD SEMUA TABEL DARI STAGING_DB ---
print(" Memuat tabel staging dari PostgreSQL...\n")

# --- BPS ---
sdf_bps_api   = read_staging("staging_bps_api_raw")
sdf_bps_dummy = read_staging("staging_bps_dummy_raw")

# --- iSIKHNAS ---
sdf_ref_hewan    = read_staging("staging_isikhnas_ref_hewan")
sdf_ref_wilayah  = read_staging("staging_isikhnas_ref_wilayah")
sdf_mutasi       = read_staging("staging_isikhnas_tr_mutasi")
sdf_laporan      = read_staging("staging_isikhnas_tr_laporan_sakit")
sdf_lab          = read_staging("staging_isikhnas_tr_hasil_lab")
sdf_rph          = read_staging("staging_isikhnas_tr_rph")

# --- PIHPS ---
sdf_pihps        = read_staging("staging_pihps_raw")

print("\n[SUCCESS] Semua tabel staging berhasil dimuat.")

# ## Cleaning & Merge Data BPS

def clean_bps_num(df, col_name: str):
    """Hapus titik ribuan, ganti koma desimal -> cast float."""
    return (df
        .withColumn(col_name,
            F.regexp_replace(F.col(col_name), r'\.', '')   
        )
        .withColumn(col_name,
            F.regexp_replace(F.col(col_name), ',', '.')     
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

sdf_bps_api_clean = sdf_bps_api_clean.withColumn("tahun", F.col("tahun").cast(IntegerType()))

print("[SUCCESS] Cleaning BPS API selesai.")
show_info(sdf_bps_api_clean, "BPS API - setelah cleaning")

# CLEANING DATA DUMMY BPS 

sdf_bps_dummy_clean = sdf_bps_dummy.withColumn(
    "tahun", F.col("tahun").cast(IntegerType())
)

print("[SUCCESS] Cleaning BPS Dummy selesai.")
show_info(sdf_bps_dummy_clean, "BPS Dummy - setelah cleaning", n=3)

# MERGE BPS API + DUMMY
sdf_bps_master = (sdf_bps_api_clean.alias("api")
    .join(
        sdf_bps_dummy_clean.alias("dum"),
        on=["provinsi", "tahun"],
        how="inner"
    )
    .select(
        F.col("api.provinsi"),
        F.col("api.tahun"),
        F.col("api.jumlah_penduduk").alias("jumlah_penduduk"),
        F.col("api.populasi_sapi").alias("populasi_sapi"),
        F.col("api.populasi_ayam").alias("populasi_ayam"),
        F.col("api.produksi_daging_ayam").alias("produksi_daging_ayam"),
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
print(f"[SUCCESS] BPS Master setelah merge: {sdf_bps_master.count()} baris")
sdf_bps_master.show(5, truncate=False)


# ---
# ## --- Normalisasi Tabel BPS & Unpivot

# TABEL ref_wilayah

window_prov = Window.orderBy("provinsi")

sdf_ref_wilayah_bps = (sdf_bps_master
    .select("provinsi").distinct()
    .orderBy("provinsi")
    .withColumn("id_wilayah", F.row_number().over(window_prov))
    .select("id_wilayah", "provinsi")
)

sdf_ref_wilayah_bps.cache()
print(f"[SUCCESS] ref_wilayah BPS: {sdf_ref_wilayah_bps.count()} provinsi")
sdf_ref_wilayah_bps.show(40, truncate=False)

# TABEL ref_komoditas
from pyspark.sql.types import StructType, StructField

ref_komoditas_data = [(1, "Sapi"), (2, "Ayam")]
sdf_ref_komoditas = spark.createDataFrame(ref_komoditas_data, ["id_komoditas", "nama_komoditas"])

print("[SUCCESS] ref_komoditas:")
sdf_ref_komoditas.show()


# MAPPING id_wilayah ke BPS Master

sdf_bps_mapped = (sdf_bps_master.alias("bps")
    .join(sdf_ref_wilayah_bps.alias("ref"), on="provinsi", how="left")
    .drop("provinsi")  
)

print(f"[SUCCESS] BPS Master setelah mapping: {sdf_bps_mapped.count()} baris")
print("Kolom:", sdf_bps_mapped.columns)

# TABEL tr_demografi

sdf_tr_demografi = (sdf_bps_mapped
    .select("id_wilayah", "tahun", "jumlah_penduduk", "growth_populasi")
    .dropDuplicates(["id_wilayah", "tahun"])
)

sdf_tr_demografi.cache()
print(f"[SUCCESS] tr_demografi: {sdf_tr_demografi.count()} baris")
sdf_tr_demografi.show(5)

# TABEL tr_statistik (UNPIVOT / MELT)

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
print(f"[SUCCESS] tr_statistik (unpivot): {sdf_tr_statistik.count()} baris")
sdf_tr_statistik.show(5)


# ---
# ## Preprocessing Lanjutan

# STANDARDISASI NAMA PROVINSI (iSIKHNAS)

sdf_ref_wilayah_isikhnas = sdf_ref_wilayah.select(
    F.col("id_wilayah").cast(IntegerType()),
    F.col("provinsi")
)

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
print(f"[SUCCESS] wilayah_master: {sdf_wilayah_master.count()} entri")
sdf_wilayah_master.show(40, truncate=False)

# HARMONISASI FORMAT TANGGAL

def parse_isikhnas_date(df, col_in: str, col_out: str = None):
    """Parse tanggal iSIKHNAS MM/dd/yy -> DATE, tambah kolom bulan & tahun."""
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

# - Laporan Sakit -
sdf_laporan_clean = parse_isikhnas_date(sdf_laporan, "tgl_lapor", "tgl_lapor")
sdf_laporan_clean = (sdf_laporan_clean
    .withColumn("id_wilayah", F.col("id_wilayah").cast(IntegerType()))
    .withColumn("jumlah_gejala", F.col("jumlah_gejala").cast(DoubleType()))
    .withColumn("jumlah_mati",   F.col("jumlah_mati").cast(DoubleType()))
)

# - Mutasi -
sdf_mutasi_clean = parse_isikhnas_date(sdf_mutasi, "tgl_mutasi", "tgl_mutasi")
sdf_mutasi_clean = (sdf_mutasi_clean
    .withColumn("id_asal",   F.col("id_asal").cast(IntegerType()))
    .withColumn("id_tujuan", F.col("id_tujuan").cast(IntegerType()))
    .withColumn("jumlah_ekor", F.col("jumlah_ekor").cast(DoubleType()))
)

# - RPH -
sdf_rph_clean = parse_isikhnas_date(sdf_rph, "tgl_potong", "tgl_potong")
sdf_rph_clean = (sdf_rph_clean
    .withColumn("id_wilayah", F.col("id_wilayah").cast(IntegerType()))
    .withColumn("berat_karkas", F.col("berat_karkas").cast(DoubleType()))
)

# - Lab -
sdf_lab_clean = parse_isikhnas_date(sdf_lab, "tgl_uji", "tgl_uji")

print("[SUCCESS] Harmonisasi tanggal selesai.")
print("\nSampel laporan_sakit:")
sdf_laporan_clean.show(3, truncate=False)
print("\nSampel rph:")
sdf_rph_clean.show(3, truncate=False)

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

map_expr = F.create_map([F.lit(x) for pair in pihps_ke_bps.items() for x in pair])

sdf_pihps_clean = (sdf_pihps
    .withColumn("waktu",  F.col("waktu").cast(TimestampType()))
    .withColumn("tgl",    F.to_date(F.col("waktu")))
    .withColumn("bulan",  F.month(F.col("waktu")).cast(IntegerType()))
    .withColumn("tahun",  F.year(F.col("waktu")).cast(IntegerType()))
    .withColumn("harga",  F.col("harga").cast(DoubleType()))
    .withColumn("nama_komoditas",
        F.when(F.lower(F.col("nama_komoditas")).contains("sapi"), F.lit("Sapi"))
         .when(F.lower(F.col("nama_komoditas")).contains("ayam"), F.lit("Ayam"))
         .otherwise(F.col("nama_komoditas"))
    )
    .withColumn("provinsi",
        F.coalesce(
            map_expr[F.upper(F.trim(F.col("provinsi")))],
            F.col("provinsi")  
        )
    )
)

sdf_pihps_clean.cache()
print(f"[SUCCESS] PIHPS clean: {sdf_pihps_clean.count()} baris")

print("\nProvinsi unik di PIHPS setelah mapping:")
sdf_pihps_clean.select("provinsi").distinct().orderBy("provinsi").show(50, truncate=False)
sdf_pihps_clean.printSchema()
sdf_pihps_clean.show(5, truncate=False)

# IMPUTASI MISSING VALUE

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
print("[SUCCESS] Imputasi selesai.")
print(f"   PIHPS missing setelah imputasi : {sdf_pihps_imputed.filter(F.col('harga').isNull()).count()}")
print(f"   tr_statistik missing populasi  : {sdf_tr_statistik_imputed.filter(F.col('populasi').isNull()).count()}")


# ---
# ## Membangun Tabel Dimensi (Surrogate Key & DDL Constraint)

# dim_prov

from pyspark.sql.window import Window

window_dim_prov = Window.orderBy("provinsi")

sdf_dim_prov = (sdf_wilayah_master
    .select("provinsi")
    .dropDuplicates()
    .orderBy("provinsi")
    .withColumn("prov_key", F.row_number().over(window_dim_prov))
    .withColumn("id_prov", F.col("prov_key"))  
    .select(
        "prov_key",
        "id_prov",
        F.col("provinsi").alias("nama_provinsi")
    )
)

sdf_dim_prov.cache()
print(f"[SUCCESS] dim_prov (FIXED): {sdf_dim_prov.count()} baris")
sdf_dim_prov.show(40, truncate=False)

# dim_komoditas
from pyspark.sql.types import StructType, StructField, IntegerType as IT, StringType as ST

schema_kom = StructType([
    StructField("komoditas_key", IT(), False),
    StructField("id_komoditas",  IT(), False),
    StructField("nama_komoditas",ST(), True),
])
sdf_dim_komoditas = spark.createDataFrame(
    [(1, 1, "Sapi"), (2, 2, "Ayam")],
    schema_kom
)

print("[SUCCESS] dim_komoditas:")
sdf_dim_komoditas.show()


# dim_waktu
tahun_min = sdf_tr_statistik_imputed.agg(F.min("tahun")).collect()[0][0]
tahun_max = sdf_tr_statistik_imputed.agg(F.max("tahun")).collect()[0][0]
print(f"   Rentang tahun: {tahun_min} - {tahun_max}")

import itertools
waktu_rows = [
    (y, m) for y in range(tahun_min, tahun_max + 1) for m in range(1, 13)
]

sdf_waktu_base = spark.createDataFrame(waktu_rows, ["tahun", "bulan"])

nama_bulan_map = {
    1:"Januari",2:"Februari",3:"Maret",4:"April",5:"Mei",6:"Juni",
    7:"Juli",8:"Agustus",9:"September",10:"Oktober",11:"November",12:"Desember"
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
print(f"[SUCCESS] dim_waktu: {sdf_dim_waktu.count()} baris")
sdf_dim_waktu.show(15)


# ---
# ## Agregasi iSIKHNAS & PIHPS

# AGREGASI iSIKHNAS (Laporan Sakit)

sdf_laporan_joined = (sdf_laporan_clean.alias("lap")
    .join(sdf_ref_hewan.alias("hw"),
          F.col("lap.id_hewan") == F.col("hw.id_hewan"),
          how="left")
    .withColumn("id_komoditas",
        F.when(F.lower(F.col("hw.nama_hewan")) == "sapi", F.lit(1))
         .when(F.lower(F.col("hw.nama_hewan")) == "ayam", F.lit(2))
         .otherwise(F.lit(0))
    )
    .withColumn("id_wilayah", F.col("lap.id_wilayah").cast(IntegerType()))
)

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

print(f"[SUCCESS] Agregasi laporan_sakit: {sdf_agg_sakit.count()} baris")
sdf_agg_sakit.show(5)

# AGREGASI iSIKHNAS (Mutasi & RPH)

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

print(f"[SUCCESS] Agregasi mutasi : {sdf_agg_mutasi.count()} baris")
print(f"[SUCCESS] Agregasi RPH    : {sdf_agg_rph.count()} baris")


# AGREGASI PIHPS (Rata-rata Harga)

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

tidak_match = sdf_pihps_prov.filter(F.col("dp.id_prov").isNull()) \
    .select("p.provinsi").distinct()
n_tidak_match = tidak_match.count()
if n_tidak_match > 0:
    print(f"  {n_tidak_match} provinsi PIHPS masih tidak match ke dim_prov:")
    tidak_match.show(truncate=False)
else:
    print("[SUCCESS] Semua provinsi PIHPS berhasil match ke dim_prov.")

sdf_agg_harga = (sdf_pihps_prov
    .filter(F.col("dp.id_prov").isNotNull())
    .groupBy(
        F.col("dp.id_prov"),
        F.col("p.bulan"),
        F.col("p.tahun"),
        "id_komoditas"
    )
    .agg(F.avg("harga").alias("avg_harga"))
    .withColumnRenamed("id_prov", "id_wilayah")
)

print(f"\n[SUCCESS] Agregasi PIHPS harga: {sdf_agg_harga.count()} baris")
print(f"   Null id_wilayah: {sdf_agg_harga.filter(F.col('id_wilayah').isNull()).count()}")
sdf_agg_harga.show(5)

# GABUNG SEMUA AGREGASI iSIKHNAS + PIHPS

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
    .filter(F.col("id_komoditas").isin([1, 2]))  
)

sdf_agg_all.cache()
print(f"[SUCCESS] Total agregasi gabungan: {sdf_agg_all.count()} baris")
sdf_agg_all.show(5)

# NORMALISASI & KONVERSI BPS

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
        (F.col("produksi_daging_kg") / F.lit(12.0)))
    .withColumn("avg_konsumsi_bulanan",
        F.when(
            F.col("dem.jumlah_penduduk").isNull() | (F.col("dem.jumlah_penduduk") <= 0),
            F.col("konsumsi_daging") / F.lit(12.0) 
        ).otherwise(
            F.col("konsumsi_daging") * F.col("dem.jumlah_penduduk") / F.lit(12.0)
        )
    )
    .withColumn("avg_permintaan_bulanan",
        (F.col("permintaan_daging") / F.lit(12.0)))
    .withColumn("avg_pemotongan_bulanan",
        (F.col("jumlah_ternak_potong") / F.lit(12.0)))
    .select(
            "st.id_wilayah", "st.tahun", "st.id_komoditas",
            "populasi_ternak", "st.harga_baseline",
            "avg_produksi_bulanan", "avg_konsumsi_bulanan",
            "avg_permintaan_bulanan", "avg_pemotongan_bulanan",
            "dem.jumlah_penduduk", 
            "dem.growth_populasi"
        )
)

sdf_bps_bulanan.cache()
print(f"[SUCCESS] BPS bulanan: {sdf_bps_bulanan.count()} baris")
sdf_bps_bulanan.show(5)


# ## Integrasi (INNER JOIN Agregasi + BPS)

# INNER JOIN AGREGASI + BPS

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
        F.coalesce(F.col("agg.sum_jumlah_sakit"),    F.lit(0.0)).alias("sum_jumlah_sakit"),
        F.coalesce(F.col("agg.sum_jumlah_mati"),     F.lit(0.0)).alias("sum_jumlah_mati"),
        F.coalesce(F.col("agg.sum_vol_mutasi"),      F.lit(0.0)).alias("sum_vol_mutasi"),
        F.coalesce(F.col("agg.sum_realisasi_karkas"),F.lit(0.0)).alias("sum_realisasi_karkas"),
        F.col("agg.avg_harga"),
        F.col("bps.populasi_ternak"),
        F.col("bps.harga_baseline"),
        F.col("bps.avg_produksi_bulanan"),
        F.col("bps.avg_konsumsi_bulanan"),
        F.col("bps.avg_permintaan_bulanan"),
        F.col("bps.avg_pemotongan_bulanan"),
        F.col("bps.jumlah_penduduk"),
        F.col("bps.growth_populasi")
    )
)

sdf_integrated.cache()
print(f"[SUCCESS] Data terintegrasi: {sdf_integrated.count()} baris")
print(f"   Null avg_harga   : {sdf_integrated.filter(F.col('avg_harga').isNull()).count()} baris")
sdf_integrated.show(5)

# ##  Menghitung `supply_risk_index`

# IMPUTASI avg_harga YANG KOSONG

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
print(f"[SUCCESS] Imputasi avg_harga selesai.")
print(f"   Null sebelum : {null_sebelum}")
print(f"   Null sesudah : {null_sesudah}")

# HITUNG KOMPONEN INDEKS (RAW)

EPS = 1e-9  
sdf_components = (sdf_with_prev_median
    .withColumn("raw_price_gap",
        F.when(
            (F.col("harga_baseline").isNull()) | (F.col("harga_baseline") <= 0) |
            (F.col("avg_harga").isNull()),
            F.lit(0.0)
        ).otherwise(
            (F.col("avg_harga") - F.col("harga_baseline")) / (F.col("harga_baseline") + F.lit(EPS))
        )
    )
    .withColumn("raw_health_impact",
        F.when(
            (F.col("populasi_ternak").isNull()) | (F.col("populasi_ternak") <= 0),
            F.lit(0.0)
        ).otherwise(
            (F.col("sum_jumlah_sakit") + F.col("sum_jumlah_mati")) /
            (F.col("populasi_ternak") + F.lit(EPS))
        )
    )
    .withColumn("raw_supply_strain",
        F.when(
            (F.col("avg_permintaan_bulanan").isNull()) | (F.col("avg_permintaan_bulanan") <= 0),
            F.lit(0.0)
        ).otherwise(
            F.col("sum_vol_mutasi") / (F.col("avg_permintaan_bulanan") + F.lit(EPS))
        )
    )
)

print("[SUCCESS] Komponen raw dihitung.")
sdf_components.select("id_wilayah","bulan","tahun","id_komoditas",
                       "raw_price_gap","raw_health_impact","raw_supply_strain").show(5)

# MIN-MAX SCALING PER KOMPONEN

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

print("[SUCCESS] Min-max scaling selesai.")
sdf_scaled.select("id_wilayah","bulan","tahun","id_komoditas",
                  "scaled_price_gap","scaled_health_impact","scaled_supply_strain").show(5)

# HITUNG supply_risk_index

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

print("[SUCCESS] supply_risk_index dihitung.")
sdf_with_index.select("id_wilayah","bulan","tahun","id_komoditas","supply_risk_index").show(10)


# BANGUN fact_supply_resilience

sdf_fact_raw = (sdf_with_index.alias("f")
    # - Join dim_prov -> prov_key -
    .join(sdf_dim_prov.alias("dp"), 
          F.col("f.id_wilayah") == F.col("dp.id_prov"), how="left")
    # - Join dim_komoditas -> komoditas_key -
    .join(sdf_dim_komoditas.alias("dk"),
          F.col("f.id_komoditas") == F.col("dk.id_komoditas"), how="left")
    # - Join dim_waktu -> waktu_key -
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
        F.col("f.jumlah_penduduk").cast(LongType()).alias("jumlah_penduduk"),
        F.col("f.growth_populasi"),
        # - Indeks Risiko -
        F.col("f.supply_risk_index"),
    )
    .filter(F.col("prov_key").isNotNull() & F.col("waktu_key").isNotNull())
)

sdf_fact_supply_resilience = sdf_fact_raw
sdf_fact_supply_resilience.cache()

total_rows = sdf_fact_supply_resilience.count()
print(f"[SUCCESS] fact_supply_resilience siap: {total_rows} baris X {len(sdf_fact_supply_resilience.columns)} kolom")
sdf_fact_supply_resilience.printSchema()

# ## Validasi Hasil Transform

print("=" * 65)
print("  RINGKASAN TABEL DIMENSI")
print("=" * 65)
print(f"  dim_prov       : {sdf_dim_prov.count()} baris")
print(f"  dim_komoditas  : {sdf_dim_komoditas.count()} baris")
print(f"  dim_waktu      : {sdf_dim_waktu.count()} baris")

print("\n" + "=" * 65)
print("  RINGKASAN TABEL FAKTA")
print("=" * 65)
print(f"  fact_supply_resilience : {sdf_fact_supply_resilience.count()} baris")

print("\n- Missing Values pada Fact Table -")
for col_name in sdf_fact_supply_resilience.columns:
    n_null = sdf_fact_supply_resilience.filter(F.col(col_name).isNull()).count()
    if n_null > 0:
        print(f"    {col_name:<30} -> {n_null} null")
    else:
        print(f"  [SUCCESS] {col_name:<30} -> 0 null")

# SIMPAN OUTPUT TRANSFORM (PARQUET ONLY)

import os

OUTPUT_DIR = r"C:\Users\anggi\Documents\KULIAH\TINGKAT 3\SEMESTER 6\TPD\PROJECT UTS\UTS-TPD-KELOMPOK-1\DATA\TRANSFORM_OUTPUT"
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

print("Menyimpan output transform ke Parquet...\n")
for name, df in tables_to_save.items():
    path = os.path.join(OUTPUT_DIR, name) 

    df_to_write = df.coalesce(1)

    (df_to_write.write
        .mode("overwrite")
        .option("compression", "snappy")
        .parquet(path)
    )
    print(f"  [SUCCESS] {name:<30} -> {path}")

sdf_bps_master.unpersist()
sdf_tr_statistik.unpersist()
sdf_agg_all.unpersist()
sdf_tr_statistik_imputed.unpersist()
sdf_bps_bulanan.unpersist()
sdf_integrated.unpersist()

print("[SUCCESS]Cache lama dibebaskan, siap simpan Parquet.")
print("\n[SUCCESS] Semua output transform tersimpan (PARQUET ONLY).")
print(f"   Output directory: {os.path.abspath(OUTPUT_DIR)}")

