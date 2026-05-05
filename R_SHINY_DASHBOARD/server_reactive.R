
# =============================================================================
# LIVESTOCK INTELLIGENCE - SERVER REACTIVE LOGIC
# =============================================================================

# Global database connection
db_con <- create_db_connection()

# =================== LOAD DIMENSION DATA ===================
dim_prov <- dbGetQuery(
  db_con, 
  "SELECT * FROM dim_prov ORDER BY nama_provinsi"
)

dim_komoditas <- dbGetQuery(
  db_con, 
  "SELECT * FROM dim_komoditas ORDER BY komoditas_key"
)

dim_waktu <- dbGetQuery(
  db_con, 
  "SELECT DISTINCT tahun, bulan FROM dim_waktu ORDER BY tahun, bulan"
)

# Load shapefile
suppressWarnings({
  shp_prov <- st_read(SPATIAL_CONFIG$shapefile_path, quiet = TRUE)
})

# =================== UPDATE FILTER CHOICES ===================
observe({
  updatePickerInput(
    session, "filter_province",
    choices = dim_prov$nama_provinsi,
    selected = NULL
  )
})

# =================== LOAD FULL OLAP CUBE (Cached) ===================
load_olap_cube <- reactive({
  query <- "
    SELECT 
      f.*,
      p.nama_provinsi, p.kode_bps,
      k.nama_komoditas,
      w.tahun, w.bulan, w.nama_bulan, w.kuartal
    FROM fact_supply_resilience f
    JOIN dim_prov p ON f.prov_key = p.prov_key
    JOIN dim_komoditas k ON f.komoditas_key = k.komoditas_key
    JOIN dim_waktu w ON f.waktu_key = w.waktu_key
    ORDER BY w.tahun DESC, w.bulan DESC, p.nama_provinsi
  "
  
  log_message("Loading OLAP Cube from database")
  data <- dbGetQuery(db_con, query)
  return(data)
})

# =================== APPLY FILTERS (OLAP OPERATIONS) ===================
filtered_data <- reactive({
  
  input$btn_apply_filters  # Reactive to button click
  
  data <- load_olap_cube()
  
  # SLICING: Province
  if (!is.null(input$filter_province) && length(input$filter_province) > 0) {
    data <- data %>%
      filter(nama_provinsi %in% input$filter_province)
    log_message(sprintf("SLICING by Province: %d records", nrow(data)))
  }
  
  # DICING: Commodity
  if (input$filter_commodity != "ALL") {
    data <- data %>%
      filter(nama_komoditas == input$filter_commodity)
    log_message(sprintf("DICING by Commodity: %d records", nrow(data)))
  }
  
  # DICING: Year Range
  data <- data %>%
    filter(tahun >= input$filter_year[1] & tahun <= input$filter_year[2])
  log_message(sprintf("DICING by Year [%d-%d]: %d records", 
                      input$filter_year[1], input$filter_year[2], nrow(data)))
  
  # DICING: Quarter
  if (length(input$filter_quarter) > 0) {
    data <- data %>%
      filter(kuartal %in% input$filter_quarter)
    log_message(sprintf("DICING by Quarter: %d records", nrow(data)))
  }
  
  return(data)
})

# =================== RESET FILTERS ===================
observeEvent(input$btn_reset_filters, {
  updatePickerInput(session, "filter_province", selected = NULL)
  updateRadioButtons(session, "filter_commodity", selected = "ALL")
  updateSliderInput(session, "filter_year", value = c(2023, 2025))
  updateCheckboxGroupInput(session, "filter_quarter", 
                          selected = c("Q1", "Q2", "Q3", "Q4"))
  log_message("Filters reset to default")
})

# =================== LOAD SPATIAL DATA WITH JOIN ===================
load_spatial_data <- reactive({
  data <- filtered_data()
  
  # ROLL-UP: Aggregate to Province level
  spatial_data <- data %>%
    group_by(prov_key, nama_provinsi, nama_komoditas) %>%
    summarise(
      supply_risk_index = mean(supply_risk_index, na.rm = TRUE),
      populasi_ternak = mean(populasi_ternak, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      sum_vol_mutasi = sum(sum_vol_mutasi, na.rm = TRUE),
      sum_realisasi_karkas = sum(sum_realisasi_karkas, na.rm = TRUE),
      avg_harga = mean(avg_harga, na.rm = TRUE),
      .groups = 'drop'
    )
  
  # Calculate disease density (cases per 1000 animals)
  spatial_data <- spatial_data %>%
    mutate(
      disease_density = ifelse(
        populasi_ternak > 0,
        (sum_jumlah_sakit / (populasi_ternak / 1000)),
        0
      )
    )
  
  # Spatial JOIN: Shapefile + Data (by province name)
  # Standardize names for joining
  shp_joined <- shp_prov %>%
    mutate(nama_provinsi = standardize_province_name(as.character(PROVINSI))) %>%
    left_join(
      spatial_data %>% filter(nama_komoditas == input$filter_commodity),
      by = "nama_provinsi"
    )
  
  return(shp_joined)
})

# =================== KPI CALCULATIONS ===================
output$kpi_critical_provs <- renderText({
  data <- filtered_data()
  critical <- data %>%
    group_by(nama_provinsi) %>%
    summarise(avg_risk = mean(supply_risk_index, na.rm = TRUE), .groups = 'drop') %>%
    filter(avg_risk >= RISK_THRESHOLDS$critical) %>%
    nrow()
  
  return(as.character(critical))
})

output$kpi_warning_provs <- renderText({
  data <- filtered_data()
  warning <- data %>%
    group_by(nama_provinsi) %>%
    summarise(avg_risk = mean(supply_risk_index, na.rm = TRUE), .groups = 'drop') %>%
    filter(avg_risk >= RISK_THRESHOLDS$warning & avg_risk < RISK_THRESHOLDS$critical) %>%
    nrow()
  
  return(as.character(warning))
})

output$kpi_avg_risk <- renderText({
  data <- filtered_data()
  avg_risk <- mean(data$supply_risk_index, na.rm = TRUE)
  return(sprintf("%.3f", avg_risk))
})

output$kpi_deficit_regions <- renderText({
  data <- filtered_data()
  deficit <- data %>%
    group_by(nama_provinsi) %>%
    summarise(
      gap = sum(sum_vol_mutasi, na.rm = TRUE) - sum(avg_permintaan_bulanan, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    filter(gap < 0) %>%
    nrow()
  
  return(as.character(deficit))
})

# =================== EXECUTIVE SUMMARY OUTPUTS ===================

# Current Alert Status Table
output$table_current_alerts <- DT::renderDataTable({
  data <- filtered_data()
  
  # Get latest month
  latest_month <- data %>%
    mutate(time_key = tahun * 100 + bulan) %>%
    summarise(max_time = max(time_key, na.rm = TRUE)) %>%
    pull(max_time)
  
  alert_data <- data %>%
    filter(tahun * 100 + bulan == latest_month) %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      supply_risk_index = mean(supply_risk_index, na.rm = TRUE),
      avg_harga = mean(avg_harga, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      sum_vol_mutasi = sum(sum_vol_mutasi, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    arrange(desc(supply_risk_index))
  
  # Add status
  alert_data <- alert_data %>%
    mutate(
      Status = ifelse(supply_risk_index >= RISK_THRESHOLDS$critical, "🔴 CRITICAL",
               ifelse(supply_risk_index >= RISK_THRESHOLDS$warning, "🟠 WARNING",
               ifelse(supply_risk_index >= RISK_THRESHOLDS$caution, "🟡 CAUTION", "🟢 SAFE")))
    ) %>%
    rename(
      `Provinsi` = nama_provinsi,
      `Komoditas` = nama_komoditas,
      `Risk Index` = supply_risk_index,
      `Avg Harga (Rp)` = avg_harga,
      `Sakit (ekor)` = sum_jumlah_sakit,
      `Mutasi (ekor)` = sum_vol_mutasi
    )
  
  DT::datatable(
    alert_data,
    options = list(
      pageLength = 10,
      searching = TRUE,
      ordering = TRUE,
      dom = 'lftip'
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = c('Risk Index'), digits = 4) %>%
    DT::formatCurrency(columns = c('Avg Harga (Rp)'), currency = "Rp")
})

# National Trend Plot
output$plot_national_trend <- renderPlotly({
  data <- filtered_data()
  
  # ROLL-UP: Aggregate to Year level
  national_trend <- data %>%
    group_by(tahun) %>%
    summarise(
      avg_risk = mean(supply_risk_index, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    arrange(tahun)
  
  plot_ly(
    data = national_trend,
    x = ~tahun,
    y = ~avg_risk,
    type = 'scatter',
    mode = 'lines+markers',
    line = list(color = COLOR_PALETTE$primary, width = 3),
    marker = list(size = 8),
    hovertemplate = '<b>Tahun:</b> %{x}<br><b>Risk Index:</b> %{y:.4f}<extra></extra>'
  ) %>%
    add_hline(y = RISK_THRESHOLDS$critical, line = list(dash = 'dash', color = COLOR_PALETTE$risk_critical),
              annotation_text = "Critical") %>%
    add_hline(y = RISK_THRESHOLDS$warning, line = list(dash = 'dash', color = COLOR_PALETTE$risk_warning),
              annotation_text = "Warning") %>%
    layout(
      title = list(text = "<b>National Risk Index Trend</b>"),
      xaxis = list(title = "<b>Year</b>"),
      yaxis = list(title = "<b>Supply Risk Index</b>", range = c(0, 1)),
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

# Risk Zones Distribution
output$plot_risk_zones <- renderPlotly({
  data <- filtered_data()
  
  # ROLL-UP: Province level
  zone_data <- data %>%
    group_by(nama_provinsi) %>%
    summarise(
      supply_risk_index = mean(supply_risk_index, na.rm = TRUE),
      populasi_ternak = mean(populasi_ternak, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(
      disease_density = ifelse(populasi_ternak > 0, 
                               sum_jumlah_sakit / (populasi_ternak / 1000), 0),
      disease_density_threshold = quantile(sum_jumlah_sakit / (populasi_ternak / 1000), 0.75, na.rm = TRUE),
      risk_zone = ifelse(
        supply_risk_index >= RISK_THRESHOLDS$warning & disease_density > disease_density_threshold,
        "RED ZONE",
        ifelse(supply_risk_index >= RISK_THRESHOLDS$warning | disease_density > disease_density_threshold,
               "ORANGE ZONE", "GREEN ZONE")
      )
    )
  
  zone_counts <- zone_data %>%
    group_by(risk_zone) %>%
    summarise(count = n(), .groups = 'drop')
  
  colors <- c("RED ZONE" = COLOR_PALETTE$risk_critical,
              "ORANGE ZONE" = COLOR_PALETTE$risk_warning,
              "GREEN ZONE" = COLOR_PALETTE$risk_safe)
  
  plot_ly(
    data = zone_counts,
    x = ~risk_zone,
    y = ~count,
    type = 'bar',
    marker = list(color = ~ifelse(risk_zone == "RED ZONE", COLOR_PALETTE$risk_critical,
                                   ifelse(risk_zone == "ORANGE ZONE", COLOR_PALETTE$risk_warning,
                                          COLOR_PALETTE$risk_safe))),
    text = ~count,
    textposition = 'outside',
    hovertemplate = '<b>%{x}</b><br>Provinsi: %{y}<extra></extra>'
  ) %>%
    layout(
      title = list(text = "<b>Risk Zone Distribution</b>"),
      xaxis = list(title = ""),
      yaxis = list(title = "<b>Jumlah Provinsi</b>"),
      showlegend = FALSE,
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

# =================== EARLY WARNING SYSTEM ===================

output$plot_top_risk_provs <- renderPlotly({
  data <- filtered_data()
  
  # ROLL-UP: Aggregate by Province & Commodity
  risk_by_prov <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      avg_risk = mean(supply_risk_index, na.rm = TRUE),
      max_risk = max(supply_risk_index, na.rm = TRUE),
      count = n(),
      .groups = 'drop'
    ) %>%
    arrange(desc(avg_risk)) %>%
    head(10)
  
  plot_ly(
    data = risk_by_prov,
    x = ~avg_risk,
    y = ~reorder(paste(nama_provinsi, "-", nama_komoditas), avg_risk),
    type = 'bar',
    orientation = 'h',
    marker = list(color = ~avg_risk,
                  colorscale = 'Reds',
                  showscale = TRUE,
                  colorbar = list(title = "Risk Index")),
    text = ~round(avg_risk, 4),
    textposition = 'outside',
    hovertemplate = '<b>%{y}</b><br>Avg Risk: %{x:.4f}<extra></extra>'
  ) %>%
    add_vline(x = RISK_THRESHOLDS$warning, line = list(dash = 'dash', color = COLOR_PALETTE$risk_warning),
              annotation_text = "Warning Threshold") %>%
    add_vline(x = RISK_THRESHOLDS$critical, line = list(dash = 'dash', color = COLOR_PALETTE$risk_critical),
              annotation_text = "Critical Threshold") %>%
    layout(
      title = list(text = "<b>Top 10 Provinsi dengan Risk Tertinggi (ROLL-UP)</b>"),
      xaxis = list(title = "<b>Average Supply Risk Index</b>", range = c(0, 1)),
      yaxis = list(title = ""),
      hovermode = 'closest',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$plot_risk_timeline <- renderPlotly({
  data <- filtered_data()
  
  # Get top 5 risk provinces
  top_provs <- data %>%
    group_by(nama_provinsi) %>%
    summarise(avg_risk = mean(supply_risk_index, na.rm = TRUE), .groups = 'drop') %>%
    arrange(desc(avg_risk)) %>%
    head(5) %>%
    pull(nama_provinsi)
  
  # DRILL-DOWN: Timeline for top provinces
  timeline_data <- data %>%
    filter(nama_provinsi %in% top_provs) %>%
    group_by(tahun, bulan, nama_provinsi, nama_komoditas) %>%
    summarise(
      avg_risk = mean(supply_risk_index, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(time_key = tahun * 100 + bulan) %>%
    arrange(time_key)
  
  plot_ly(
    data = timeline_data,
    x = ~time_key,
    y = ~avg_risk,
    color = ~nama_provinsi,
    type = 'scatter',
    mode = 'lines+markers',
    hovertemplate = '<b>%{fullData.name}</b><br>Period: %{x}<br>Risk: %{y:.4f}<extra></extra>'
  ) %>%
    add_hline(y = RISK_THRESHOLDS$critical, line = list(dash = 'dash', color = COLOR_PALETTE$risk_critical)) %>%
    add_hline(y = RISK_THRESHOLDS$warning, line = list(dash = 'dash', color = COLOR_PALETTE$risk_warning)) %>%
    layout(
      title = list(text = "<b>Risk Timeline: Top 5 Berisiko (DRILL-DOWN: Monthly)</b>"),
      xaxis = list(title = "<b>Periode (YYYYMM)</b>"),
      yaxis = list(title = "<b>Supply Risk Index</b>", range = c(0, 1)),
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$plot_risk_components <- renderPlotly({
  data <- filtered_data()
  
  # Latest period - ROLL-UP to understand components
  latest_month <- data %>%
    mutate(time_key = tahun * 100 + bulan) %>%
    summarise(max_time = max(time_key, na.rm = TRUE)) %>%
    pull(max_time)
  
  comp_data <- data %>%
    filter(tahun * 100 + bulan == latest_month) %>%
    group_by(nama_komoditas) %>%
    summarise(
      price_gap = mean((avg_harga - harga_baseline) / harga_baseline, na.rm = TRUE),
      health_impact = mean((sum_jumlah_sakit + sum_jumlah_mati) / populasi_ternak, na.rm = TRUE),
      supply_strain = mean((supply_risk_index * 3 - price_gap - health_impact), na.rm = TRUE),
      .groups = 'drop'
    )
  
  plot_ly(
    data = comp_data,
    x = ~nama_komoditas,
    y = ~price_gap,
    name = 'Price Gap',
    type = 'bar',
    marker = list(color = '#0066cc')
  ) %>%
    add_trace(y = ~health_impact, name = 'Health Impact', marker = list(color = '#FF6B6B')) %>%
    add_trace(y = ~supply_strain, name = 'Supply Strain', marker = list(color = '#FFA502')) %>%
    layout(
      title = list(text = "<b>Risk Index Components (Latest Period)</b>"),
      xaxis = list(title = "<b>Komoditas</b>"),
      yaxis = list(title = "<b>Component Value</b>"),
      barmode = 'group',
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$table_detailed_risk <- DT::renderDataTable({
  data <- filtered_data()
  
  # DRILL-DOWN: Monthly detail
  detail_data <- data %>%
    select(nama_provinsi, nama_komoditas, tahun, bulan, 
           supply_risk_index, avg_harga, sum_jumlah_sakit, 
           sum_vol_mutasi, harga_baseline) %>%
    arrange(desc(tahun), desc(bulan), desc(supply_risk_index)) %>%
    rename(
      `Provinsi` = nama_provinsi,
      `Komoditas` = nama_komoditas,
      `Tahun` = tahun,
      `Bulan` = bulan,
      `Risk Index` = supply_risk_index,
      `Harga (Rp)` = avg_harga,
      `Sakit (ekor)` = sum_jumlah_sakit,
      `Mutasi (ekor)` = sum_vol_mutasi,
      `Harga Baseline` = harga_baseline
    )
  
  DT::datatable(
    detail_data,
    options = list(
      pageLength = 15,
      searching = TRUE,
      ordering = TRUE,
      dom = 'lftip'
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = c('Risk Index'), digits = 4) %>%
    DT::formatCurrency(columns = c('Harga (Rp)', 'Harga Baseline'), currency = "Rp")
})

# =================== PRICE VS DISEASE CORRELATION ===================

output$table_correlation_summary <- DT::renderDataTable({
  data <- filtered_data()
  
  # Calculate Pearson correlation by commodity
  corr_results <- list()
  
  for (comm in unique(data$nama_komoditas)) {
    comm_data <- data %>%
      filter(nama_komoditas == comm) %>%
      filter(!is.na(avg_harga) & !is.na(sum_jumlah_sakit))
    
    if (nrow(comm_data) > 2) {
      test <- cor.test(comm_data$avg_harga, comm_data$sum_jumlah_sakit, 
                       method = "pearson")
      
      corr_results[[comm]] <- data.frame(
        Komoditas = comm,
        Correlation = test$estimate,
        P_Value = test$p.value,
        N_Observations = nrow(comm_data),
        Strength = ifelse(abs(test$estimate) >= 0.7, "KUAT",
                         ifelse(abs(test$estimate) >= 0.5, "SEDANG", "LEMAH")),
        Significant = ifelse(test$p.value < 0.05, "Ya", "Tidak")
      )
    }
  }
  
  corr_df <- do.call(rbind, corr_results)
  rownames(corr_df) <- NULL
  
  DT::datatable(
    corr_df,
    options = list(
      pageLength = 5,
      dom = 't'
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = c('Correlation', 'P_Value'), digits = 4)
})

output$plot_timeseries_sapi <- renderPlotly({
  data <- filtered_data() %>%
    filter(nama_komoditas == 'Sapi')
  
  if (nrow(data) == 0) {
    return(plotly_empty())
  }
  
  ts_data <- data %>%
    group_by(tahun, bulan) %>%
    summarise(
      avg_harga = mean(avg_harga, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(time_key = tahun * 100 + bulan) %>%
    arrange(time_key)
  
  fig <- make_subplots(specs = list(list(secondary_y = TRUE)))
  
  fig <- fig %>%
    add_trace(
      data = ts_data,
      x = ~time_key, y = ~avg_harga,
      type = 'scatter', mode = 'lines+markers',
      name = 'Harga Rata-rata',
      line = list(color = '#0066cc', width = 2),
      secondary_y = FALSE
    ) %>%
    add_trace(
      data = ts_data,
      x = ~time_key, y = ~sum_jumlah_sakit,
      type = 'bar',
      name = 'Jumlah Sakit',
      marker = list(color = '#FF6B6B', opacity = 0.6),
      secondary_y = TRUE
    ) %>%
    layout(
      title = "<b>Harga vs Wabah - Sapi (DRILL-DOWN)</b>",
      xaxis = list(title = "Periode (YYYYMM)"),
      yaxis = list(title = "<b>Harga (Rp)</b>"),
      yaxis2 = list(title = "<b>Jumlah Sakit (ekor)</b>", overlaying = "y", side = "right"),
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
  
  return(fig)
})

output$plot_timeseries_ayam <- renderPlotly({
  data <- filtered_data() %>%
    filter(nama_komoditas == 'Ayam')
  
  if (nrow(data) == 0) {
    return(plotly_empty())
  }
  
  ts_data <- data %>%
    group_by(tahun, bulan) %>%
    summarise(
      avg_harga = mean(avg_harga, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(time_key = tahun * 100 + bulan) %>%
    arrange(time_key)
  
  fig <- make_subplots(specs = list(list(secondary_y = TRUE)))
  
  fig <- fig %>%
    add_trace(
      data = ts_data,
      x = ~time_key, y = ~avg_harga,
      type = 'scatter', mode = 'lines+markers',
      name = 'Harga Rata-rata',
      line = list(color = '#0066cc', width = 2),
      secondary_y = FALSE
    ) %>%
    add_trace(
      data = ts_data,
      x = ~time_key, y = ~sum_jumlah_sakit,
      type = 'bar',
      name = 'Jumlah Sakit',
      marker = list(color = '#FF6B6B', opacity = 0.6),
      secondary_y = TRUE
    ) %>%
    layout(
      title = "<b>Harga vs Wabah - Ayam (DRILL-DOWN)</b>",
      xaxis = list(title = "Periode (YYYYMM)"),
      yaxis = list(title = "<b>Harga (Rp)</b>"),
      yaxis2 = list(title = "<b>Jumlah Sakit (ekor)</b>", overlaying = "y", side = "right"),
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
  
  return(fig)
})

output$plot_scatter_sapi <- renderPlotly({
  data <- filtered_data() %>%
    filter(nama_komoditas == 'Sapi',
           !is.na(avg_harga), !is.na(sum_jumlah_sakit))
  
  if (nrow(data) < 2) {
    return(plotly_empty())
  }
  
  plot_ly(
    data = data,
    x = ~sum_jumlah_sakit,
    y = ~avg_harga,
    type = 'scatter',
    mode = 'markers',
    marker = list(size = 8, color = '#0066cc', opacity = 0.7),
    text = ~paste("Periode:", tahun, "-", bulan),
    hovertemplate = '<b>Sapi</b><br>Sakit: %{x} ekor<br>Harga: Rp %{y:,.0f}<br>%{text}<extra></extra>'
  ) %>%
    layout(
      title = "<b>Scatter: Harga vs Wabah - Sapi</b>",
      xaxis = list(title = "<b>Jumlah Sakit (ekor)</b>"),
      yaxis = list(title = "<b>Harga Rata-rata (Rp)</b>"),
      hovermode = 'closest',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$plot_scatter_ayam <- renderPlotly({
  data <- filtered_data() %>%
    filter(nama_komoditas == 'Ayam',
           !is.na(avg_harga), !is.na(sum_jumlah_sakit))
  
  if (nrow(data) < 2) {
    return(plotly_empty())
  }
  
  plot_ly(
    data = data,
    x = ~sum_jumlah_sakit,
    y = ~avg_harga,
    type = 'scatter',
    mode = 'markers',
    marker = list(size = 8, color = '#4ECDC4', opacity = 0.7),
    text = ~paste("Periode:", tahun, "-", bulan),
    hovertemplate = '<b>Ayam</b><br>Sakit: %{x} ekor<br>Harga: Rp %{y:,.0f}<br>%{text}<extra></extra>'
  ) %>%
    layout(
      title = "<b>Scatter: Harga vs Wabah - Ayam</b>",
      xaxis = list(title = "<b>Jumlah Sakit (ekor)</b>"),
      yaxis = list(title = "<b>Harga Rata-rata (Rp)</b>"),
      hovermode = 'closest',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$text_correlation_interpretation <- renderUI({
  data <- filtered_data()
  
  interpretations <- list()
  
  for (comm in unique(data$nama_komoditas)) {
    comm_data <- data %>%
      filter(nama_komoditas == comm) %>%
      filter(!is.na(avg_harga) & !is.na(sum_jumlah_sakit))
    
    if (nrow(comm_data) > 2) {
      test <- cor.test(comm_data$avg_harga, comm_data$sum_jumlah_sakit)
      r <- test$estimate
      p <- test$p.value
      
      strength <- ifelse(abs(r) >= 0.7, "KUAT",
                        ifelse(abs(r) >= 0.5, "SEDANG", "LEMAH"))
      direction <- ifelse(r > 0, "positif", "negatif")
      sig <- ifelse(p < 0.05, "signifikan", "tidak signifikan")
      
      interp <- sprintf(
        "<b>%s:</b> Korelasi %s %s (%s, p=%.4f)<br/>",
        comm, strength, direction, sig, p
      )
      
      if (abs(r) >= 0.7) {
        interp <- paste0(interp, "⚠️ Kenaikan harga SANGAT terkait dengan wabah penyakit!<br/>")
      } else if (abs(r) >= 0.5) {
        interp <- paste0(interp, "⚠️ Kenaikan harga cukup terkait dengan wabah penyakit.<br/>")
      } else {
        interp <- paste0(interp, "ℹ️ Kenaikan harga kemungkinan besar bukan dari wabah (faktor lain dominan).<br/>")
      }
      
      interpretations[[comm]] <- HTML(interp)
    }
  }
  
  return(HTML(paste(interpretations, collapse = "")))
})

# =================== SUPPLY VS DEMAND GAP ===================

output$table_gap_summary <- DT::renderDataTable({
  data <- filtered_data()
  
  # ROLL-UP: National level
  gap_summary <- data %>%
    group_by(nama_komoditas) %>%
    summarise(
      total_mutasi_ekor = sum(sum_vol_mutasi, na.rm = TRUE),
      total_permintaan_ekor = sum(avg_permintaan_bulanan, na.rm = TRUE),
      gap_ekor = total_mutasi_ekor - total_permintaan_ekor,
      total_karkas_kg = sum(sum_realisasi_karkas, na.rm = TRUE),
      total_konsumsi_kg = sum(avg_konsumsi_bulanan, na.rm = TRUE),
      gap_kg = total_karkas_kg - total_konsumsi_kg,
      .groups = 'drop'
    ) %>%
    mutate(
      gap_pct_ekor = (gap_ekor / total_permintaan_ekor * 100),
      gap_pct_kg = (gap_kg / total_konsumsi_kg * 100),
      status_ekor = ifelse(gap_ekor > 0, "✓ SURPLUS", "✗ DEFICIT"),
      status_kg = ifelse(gap_kg > 0, "✓ SURPLUS", "✗ DEFICIT")
    ) %>%
    rename(
      `Komoditas` = nama_komoditas,
      `Total Mutasi (ekor)` = total_mutasi_ekor,
      `Target Permintaan (ekor)` = total_permintaan_ekor,
      `Gap Ekor` = gap_ekor,
      `Gap % Ekor` = gap_pct_ekor,
      `Status Logistik` = status_ekor,
      `Total Karkas (Kg)` = total_karkas_kg,
      `Target Konsumsi (Kg)` = total_konsumsi_kg,
      `Gap Kg` = gap_kg,
      `Gap % Kg` = gap_pct_kg,
      `Status Konsumsi` = status_kg
    )
  
  DT::datatable(
    gap_summary,
    options = list(
      pageLength = 5,
      dom = 't',
      scrollX = TRUE
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = grep("^[TG]", names(gap_summary)), digits = 0)
})

output$plot_gap_timeline <- renderPlotly({
  data <- filtered_data()
  
  # DRILL-DOWN: Monthly aggregation
  gap_timeline <- data %>%
    group_by(tahun, bulan, nama_komoditas) %>%
    summarise(
      gap_ekor = sum(sum_vol_mutasi, na.rm = TRUE) - sum(avg_permintaan_bulanan, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(time_key = tahun * 100 + bulan) %>%
    arrange(time_key)
  
  plot_ly(
    data = gap_timeline,
    x = ~time_key,
    y = ~gap_ekor,
    color = ~nama_komoditas,
    type = 'bar',
    hovertemplate = '<b>%{fullData.name}</b><br>Periode: %{x}<br>Gap: %{y:,.0f} ekor<extra></extra>'
  ) %>%
    add_hline(y = 0, line = list(color = 'black', width = 2, dash = 'dash')) %>%
    layout(
      title = "<b>Supply-Demand Gap Timeline (DRILL-DOWN: Monthly)</b>",
      xaxis = list(title = "<b>Periode (YYYYMM)</b>"),
      yaxis = list(title = "<b>Gap (ekor)</b>"),
      barmode = 'group',
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$plot_deficit_provinces <- renderPlotly({
  data <- filtered_data()
  
  # ROLL-UP: Province level
  deficit_prov <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      gap_ekor = sum(sum_vol_mutasi, na.rm = TRUE) - sum(avg_permintaan_bulanan, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    filter(gap_ekor < 0) %>%
    arrange(gap_ekor) %>%
    head(10)
  
  plot_ly(
    data = deficit_prov,
    x = ~gap_ekor,
    y = ~reorder(paste(nama_provinsi, "-", nama_komoditas), gap_ekor),
    type = 'bar',
    orientation = 'h',
    marker = list(color = '#FF6B6B'),
    text = ~round(gap_ekor, 0),
    textposition = 'outside',
    hovertemplate = '<b>%{y}</b><br>Gap: %{x:,.0f} ekor<extra></extra>'
  ) %>%
    layout(
      title = "<b>Top 10 Wilayah DEFICIT (ROLL-UP: Provinsi)</b>",
      xaxis = list(title = "<b>Gap (ekor) - Negatif = Deficit</b>"),
      yaxis = list(title = ""),
      hovermode = 'closest',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$plot_gap_distribution <- renderPlotly({
  data <- filtered_data()
  
  # ROLL-UP: Province level
  gap_dist <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      gap_ekor = sum(sum_vol_mutasi, na.rm = TRUE) - sum(avg_permintaan_bulanan, na.rm = TRUE),
      .groups = 'drop'
    )
  
  plot_ly(
    data = gap_dist,
    x = ~nama_komoditas,
    y = ~gap_ekor,
    color = ~nama_komoditas,
    type = 'box',
    boxmean = 'sd',
    hovertemplate = '<b>%{fullData.name}</b><br>Gap: %{y:,.0f} ekor<extra></extra>'
  ) %>%
    add_hline(y = 0, line = list(color = 'black', width = 2, dash = 'dash')) %>%
    layout(
      title = "<b>Gap Distribution by Commodity</b>",
      xaxis = list(title = "<b>Komoditas</b>"),
      yaxis = list(title = "<b>Gap (ekor)</b>"),
      showlegend = FALSE,
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
})

output$table_detailed_gap <- DT::renderDataTable({
  data <- filtered_data()
  
  # DRILL-DOWN: Monthly detail by province
  detail_gap <- data %>%
    group_by(nama_provinsi, nama_komoditas, tahun, bulan) %>%
    summarise(
      mutasi = sum(sum_vol_mutasi, na.rm = TRUE),
      permintaan = mean(avg_permintaan_bulanan, na.rm = TRUE),
      karkas = sum(sum_realisasi_karkas, na.rm = TRUE),
      konsumsi = mean(avg_konsumsi_bulanan, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(
      gap_ekor = mutasi - permintaan,
      gap_kg = karkas - konsumsi
    ) %>%
    arrange(desc(tahun), desc(bulan), desc(gap_ekor)) %>%
    rename(
      `Provinsi` = nama_provinsi,
      `Komoditas` = nama_komoditas,
      `Tahun` = tahun,
      `Bulan` = bulan,
      `Mutasi (ekor)` = mutasi,
      `Permintaan (ekor)` = permintaan,
      `Gap Ekor` = gap_ekor,
      `Karkas (Kg)` = karkas,
      `Konsumsi (Kg)` = konsumsi,
      `Gap Kg` = gap_kg
    )
  
  DT::datatable(
    detail_gap,
    options = list(
      pageLength = 15,
      searching = TRUE,
      ordering = TRUE,
      dom = 'lftip'
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = c('Mutasi (ekor)', 'Permintaan (ekor)', 'Gap Ekor', 
                                'Karkas (Kg)', 'Konsumsi (Kg)', 'Gap Kg'), digits = 0)
})

# =================== SPATIAL MAPPING ===================

output$map_spatial_risk <- renderLeaflet({
  spatial_data <- load_spatial_data()
  
  # Filter out NA geometries
  spatial_data <- spatial_data %>%
    filter(!st_is_empty(spatial_data))
  
  # Color palette for risk index
  pal <- colorNumeric(
    palette = "YlOrRd",
    domain = c(0, 1),
    na.color = "#BDBDBD"
  )
  
  # Create popup text
  popup_text <- paste(
    "<b>", spatial_data$nama_provinsi, "</b><br/>",
    "Komoditas:", spatial_data$nama_komoditas, "<br/>",
    "Risk Index:", round(spatial_data$supply_risk_index, 4), "<br/>",
    "Populasi:", format(round(spatial_data$populasi_ternak), big.mark = ","), " ekor<br/>",
    "Penyakit:", format(round(spatial_data$sum_jumlah_sakit), big.mark = ","), " kasus"
  )
  
  leaflet(spatial_data) %>%
    addTiles() %>%
    setView(lng = SPATIAL_CONFIG$center_lon, 
            lat = SPATIAL_CONFIG$center_lat,
            zoom = SPATIAL_CONFIG$zoom_level) %>%
    addPolygons(
      fillColor = ~pal(supply_risk_index),
      weight = 2,
      opacity = 0.8,
      color = "white",
      dashArray = "3",
      fillOpacity = 0.7,
      popup = popup_text,
      highlightOptions = highlightOptions(
        weight = 5,
        color = "#666",
        dashArray = "",
        fillOpacity = 0.9,
        bringToFront = TRUE
      )
    ) %>%
    addLegend(
      pal = pal,
      values = ~supply_risk_index,
      opacity = 0.7,
      title = "Supply Risk Index",
      position = "bottomright"
    )
})

output$plot_zone_distribution <- renderPlotly({
  data <- filtered_data()
  
  # ROLL-UP: Province level
  zone_data <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      supply_risk_index = mean(supply_risk_index, na.rm = TRUE),
      populasi_ternak = mean(populasi_ternak, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(
      disease_density = ifelse(populasi_ternak > 0,
                               sum_jumlah_sakit / (populasi_ternak / 1000), 0),
      disease_density_threshold = quantile(sum_jumlah_sakit / (populasi_ternak / 1000), 0.75, na.rm = TRUE),
      risk_zone = ifelse(
        supply_risk_index >= RISK_THRESHOLDS$warning & disease_density > disease_density_threshold,
        "RED ZONE",
        ifelse(supply_risk_index >= RISK_THRESHOLDS$warning | disease_density > disease_density_threshold,
               "ORANGE ZONE", "GREEN ZONE")
      )
    )
  
  zone_counts <- zone_data %>%
    group_by(risk_zone) %>%
    summarise(count = n(), .groups = 'drop')
  
  plot_ly(
    data = zone_counts,
    labels = ~risk_zone,
    values = ~count,
    type = 'pie',
    marker = list(
      colors = c("RED ZONE" = COLOR_PALETTE$risk_critical,
                 "ORANGE ZONE" = COLOR_PALETTE$risk_warning,
                 "GREEN ZONE" = COLOR_PALETTE$risk_safe)
    ),
    textposition = 'inside',
    textinfo = 'label+percent',
    hovertemplate = '<b>%{label}</b><br>Provinsi: %{value}<extra></extra>'
  ) %>%
    layout(
      title = "<b>Risk Zone Classification Distribution</b>",
      paper_bgcolor = 'white'
    )
})

output$plot_risk_bubble <- renderPlotly({
  data <- filtered_data()
  
  # ROLL-UP: Province level
  bubble_data <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      supply_risk_index = mean(supply_risk_index, na.rm = TRUE),
      populasi_ternak = mean(populasi_ternak, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(
      disease_density = ifelse(populasi_ternak > 0,
                               sum_jumlah_sakit / (populasi_ternak / 1000), 0),
      disease_density_threshold = quantile(sum_jumlah_sakit / (populasi_ternak / 1000), 0.75, na.rm = TRUE),
      risk_zone = ifelse(
        supply_risk_index >= RISK_THRESHOLDS$warning & disease_density > disease_density_threshold,
        "RED ZONE",
        ifelse(supply_risk_index >= RISK_THRESHOLDS$warning | disease_density > disease_density_threshold,
               "ORANGE ZONE", "GREEN ZONE")
      )
    )
  
  plot_ly(
    data = bubble_data,
    x = ~populasi_ternak,
    y = ~disease_density,
    size = ~supply_risk_index,
    color = ~risk_zone,
    text = ~nama_provinsi,
    type = 'scatter',
    mode = 'markers',
    marker = list(
      sizemode = 'diameter',
      sizeref = 2 * max(bubble_data$supply_risk_index) / (60^2),
      line = list(width = 1, color = 'white')
    ),
    colors = c("RED ZONE" = COLOR_PALETTE$risk_critical,
               "ORANGE ZONE" = COLOR_PALETTE$risk_warning,
               "GREEN ZONE" = COLOR_PALETTE$risk_safe),
    hovertemplate = '<b>%{text}</b><br>Population: %{x:,.0f}<br>Disease Density: %{y:.2f}<br>Risk Index: %{marker.size:.3f}<extra></extra>'
  ) %>%
    layout(
      title = "<b>Spatial Risk: Population vs Disease Density (ROLL-UP)</b>",
      xaxis = list(title = "<b>Populasi Ternak (ekor)</b>", type = "log"),
      yaxis = list(title = "<b>Densitas Penyakit (per 1000 ekor)</b>"),
      hovermode = 'closest',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white',
      showlegend = TRUE
    )
})

output$table_spatial_risk <- DT::renderDataTable({
  data <- filtered_data()
  
  # ROLL-UP: Province level (select one commodity)
  spatial_table <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      supply_risk_index = mean(supply_risk_index, na.rm = TRUE),
      populasi_ternak = mean(populasi_ternak, na.rm = TRUE),
      sum_jumlah_sakit = sum(sum_jumlah_sakit, na.rm = TRUE),
      sum_vol_mutasi = sum(sum_vol_mutasi, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    mutate(
      disease_density = ifelse(populasi_ternak > 0,
                               sum_jumlah_sakit / (populasi_ternak / 1000), 0),
      disease_density_threshold = quantile(sum_jumlah_sakit / (populasi_ternak / 1000), 0.75, na.rm = TRUE),
      risk_zone = ifelse(
        supply_risk_index >= RISK_THRESHOLDS$warning & disease_density > disease_density_threshold,
        "RED ZONE - Prioritas Utama",
        ifelse(supply_risk_index >= RISK_THRESHOLDS$warning | disease_density > disease_density_threshold,
               "ORANGE ZONE - Perhatian", "GREEN ZONE - Stabil")
      )
    ) %>%
    arrange(desc(supply_risk_index)) %>%
    rename(
      `Provinsi` = nama_provinsi,
      `Komoditas` = nama_komoditas,
      `Risk Index` = supply_risk_index,
      `Populasi (ekor)` = populasi_ternak,
      `Penyakit (kasus)` = sum_jumlah_sakit,
      `Densitas/1000` = disease_density,
      `Mutasi (ekor)` = sum_vol_mutasi,
      `Risk Zone` = risk_zone
    )
  
  DT::datatable(
    spatial_table,
    options = list(
      pageLength = 15,
      searching = TRUE,
      ordering = TRUE,
      dom = 'lftip'
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = c('Risk Index', 'Densitas/1000'), digits = 4) %>%
    DT::formatCurrency(columns = c('Populasi (ekor)', 'Penyakit (kasus)', 'Mutasi (ekor)'), 
                       currency = "", interval = 3, mark = ",", digits = 0)
})

# =================== SUPPLY DEPENDENCY ===================

output$table_dependency_summary <- DT::renderDataTable({
  data <- filtered_data()
  
  # Assuming Jabodetabek = Jakarta, Bogor, Depok, Tangerang, Bekasi
  jabodetabek_provs <- c("DKI JAKARTA", "JAWA BARAT", "BANTEN")
  
  # Filter incoming supplies to Jabodetabek
  # Assuming sum_vol_mutasi includes destinations
  # For demonstration, we'll calculate concentration by source
  
  dependency <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      total_supply = sum(sum_vol_mutasi, na.rm = TRUE),
      avg_risk_index = mean(supply_risk_index, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    group_by(nama_komoditas) %>%
    mutate(
      total_national = sum(total_supply, na.rm = TRUE),
      supply_pct = (total_supply / total_national * 100),
      cumulative_pct = cumsum(supply_pct),
      is_key_supplier = ifelse(cumulative_pct <= 80, "Ya", "Tidak")
    ) %>%
    arrange(desc(supply_pct)) %>%
    rename(
      `Provinsi` = nama_provinsi,
      `Komoditas` = nama_komoditas,
      `Total Supply (ekor)` = total_supply,
      `Supply %` = supply_pct,
      `Cumulative %` = cumulative_pct,
      `Avg Risk` = avg_risk_index,
      `Key Supplier (80%)` = is_key_supplier
    )
  
  DT::datatable(
    dependency,
    options = list(
      pageLength = 15,
      searching = TRUE,
      ordering = TRUE,
      dom = 'lftip'
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = c('Total Supply (ekor)', 'Supply %', 'Cumulative %', 'Avg Risk'), 
                    digits = c(0, 2, 2, 4))
})

output$plot_pareto_sapi <- renderPlotly({
  data <- filtered_data() %>%
    filter(nama_komoditas == 'Sapi')
  
  if (nrow(data) == 0) {
    return(plotly_empty())
  }
  
  # ROLL-UP: Province level
  pareto_data <- data %>%
    group_by(nama_provinsi) %>%
    summarise(
      total_supply = sum(sum_vol_mutasi, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    arrange(desc(total_supply)) %>%
    mutate(
      cumulative_supply = cumsum(total_supply),
      cumulative_pct = cumulative_supply / sum(total_supply) * 100
    )
  
  fig <- make_subplots(specs = list(list(secondary_y = TRUE)))
  
  fig <- fig %>%
    add_trace(
      data = pareto_data,
      x = ~reorder(nama_provinsi, -total_supply),
      y = ~total_supply,
      type = 'bar',
      name = 'Supply Volume',
      marker = list(color = '#0066cc'),
      secondary_y = FALSE
    ) %>%
    add_trace(
      data = pareto_data,
      x = ~reorder(nama_provinsi, -total_supply),
      y = ~cumulative_pct,
      type = 'scatter',
      mode = 'lines+markers',
      name = 'Cumulative %',
      line = list(color = '#FF6B6B', width = 3),
      marker = list(size = 8),
      secondary_y = TRUE
    ) %>%
    layout(
      title = "<b>Pareto Chart: Supply Concentration - Sapi</b>",
      xaxis = list(title = "<b>Provinsi</b>"),
      yaxis = list(title = "<b>Supply Volume (ekor)</b>"),
      yaxis2 = list(title = "<b>Cumulative %</b>", range = c(0, 100)),
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
  
  return(fig)
})

output$plot_pareto_ayam <- renderPlotly({
  data <- filtered_data() %>%
    filter(nama_komoditas == 'Ayam')
  
  if (nrow(data) == 0) {
    return(plotly_empty())
  }
  
  # ROLL-UP: Province level
  pareto_data <- data %>%
    group_by(nama_provinsi) %>%
    summarise(
      total_supply = sum(sum_vol_mutasi, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    arrange(desc(total_supply)) %>%
    mutate(
      cumulative_supply = cumsum(total_supply),
      cumulative_pct = cumulative_supply / sum(total_supply) * 100
    )
  
  fig <- make_subplots(specs = list(list(secondary_y = TRUE)))
  
  fig <- fig %>%
    add_trace(
      data = pareto_data,
      x = ~reorder(nama_provinsi, -total_supply),
      y = ~total_supply,
      type = 'bar',
      name = 'Supply Volume',
      marker = list(color = '#4ECDC4'),
      secondary_y = FALSE
    ) %>%
    add_trace(
      data = pareto_data,
      x = ~reorder(nama_provinsi, -total_supply),
      y = ~cumulative_pct,
      type = 'scatter',
      mode = 'lines+markers',
      name = 'Cumulative %',
      line = list(color = '#FF6B6B', width = 3),
      marker = list(size = 8),
      secondary_y = TRUE
    ) %>%
    layout(
      title = "<b>Pareto Chart: Supply Concentration - Ayam</b>",
      xaxis = list(title = "<b>Provinsi</b>"),
      yaxis = list(title = "<b>Supply Volume (ekor)</b>"),
      yaxis2 = list(title = "<b>Cumulative %</b>", range = c(0, 100)),
      hovermode = 'x unified',
      plot_bgcolor = '#f8f9fa',
      paper_bgcolor = 'white'
    )
  
  return(fig)
})

output$text_vulnerability_assessment <- renderUI({
  data <- filtered_data()
  
  # Identify key suppliers with high risk
  vulnerable <- data %>%
    group_by(nama_provinsi, nama_komoditas) %>%
    summarise(
      total_supply = sum(sum_vol_mutasi, na.rm = TRUE),
      avg_risk = mean(supply_risk_index, na.rm = TRUE),
      .groups = 'drop'
    ) %>%
    group_by(nama_komoditas) %>%
    mutate(supply_pct = total_supply / sum(total_supply) * 100) %>%
    filter(supply_pct >= 5 & avg_risk >= RISK_THRESHOLDS$warning) %>%
    arrange(desc(supply_pct))
  
  if (nrow(vulnerable) == 0) {
    return(HTML("<p>✓ Tidak ada supplier kunci dengan risk tinggi saat ini.</p>"))
  }
  
  vuln_text <- "<p><b>⚠️ Peringatan: Supplier Kunci Dengan Risk Tinggi</b></p>"
  for (i in 1:nrow(vulnerable)) {
    row <- vulnerable[i, ]
    vuln_text <- paste0(
      vuln_text,
      sprintf("<p>• <b>%s - %s:</b> Supply %.1f%% dari nasional, Risk Index %.3f (%s)<br/>",
              row$nama_provinsi, row$nama_komoditas, row$supply_pct, row$avg_risk,
              if (row$avg_risk >= RISK_THRESHOLDS$critical) "CRITICAL" else "WARNING"),
      sprintf("   ⚠️ Jika terjadi guncangan di provinsi ini → risiko krisis pasokan nasional!</p>")
    )
  }
  
  return(HTML(vuln_text))
})

# =================== DATA EXPLORER ===================

output$table_explorer <- DT::renderDataTable({
  data <- filtered_data()
  
  explorer_data <- data %>%
    select(nama_provinsi, nama_komoditas, tahun, bulan, 
           supply_risk_index, avg_harga, sum_jumlah_sakit, sum_jumlah_mati,
           sum_vol_mutasi, sum_realisasi_karkas, populasi_ternak, 
           avg_permintaan_bulanan, avg_konsumsi_bulanan) %>%
    rename(
      `Provinsi` = nama_provinsi,
      `Komoditas` = nama_komoditas,
      `Tahun` = tahun,
      `Bulan` = bulan,
      `Risk Index` = supply_risk_index,
      `Harga (Rp)` = avg_harga,
      `Sakit` = sum_jumlah_sakit,
      `Mati` = sum_jumlah_mati,
      `Mutasi (ekor)` = sum_vol_mutasi,
      `Karkas (Kg)` = sum_realisasi_karkas,
      `Populasi (ekor)` = populasi_ternak,
      `Permintaan (ekor)` = avg_permintaan_bulanan,
      `Konsumsi (Kg)` = avg_konsumsi_bulanan
    )
  
  DT::datatable(
    explorer_data,
    options = list(
      pageLength = 25,
      searching = TRUE,
      ordering = TRUE,
      dom = 'lftip',
      scrollX = TRUE
    ),
    rownames = FALSE
  ) %>%
    DT::formatRound(columns = c('Risk Index'), digits = 4) %>%
    DT::formatCurrency(columns = c('Harga (Rp)'), currency = "Rp")
})

output$btn_download_csv <- downloadHandler(
  filename = function() {
    paste0("livestock_intelligence_", Sys.Date(), ".csv")
  },
  content = function(file) {
    write.csv(filtered_data(), file, row.names = FALSE)
  }
)

output$btn_download_xlsx <- downloadHandler(
  filename = function() {
    paste0("livestock_intelligence_", Sys.Date(), ".xlsx")
  },
  content = function(file) {
    writexl::write_xlsx(filtered_data(), file)
  }
)

output$btn_download_pdf <- downloadHandler(
  filename = function() {
    paste0("livestock_intelligence_", Sys.Date(), ".pdf")
  },
  content = function(file) {
    # Simple PDF export using gridExtra
    pdf(file, width = 14, height = 8)
    grid.table(head(filtered_data(), 100))
    dev.off()
  }
)

# On session close, close database connection
session$onSessionEnded(function() {
  log_message("Closing database connection")
  dbDisconnect(db_con)
})
