# ==============================================================================
# LIVESTOCK INTELLIGENCE - R SHINY DASHBOARD
# server.R: Reactive Logic, Database Queries, OLAP Operations & Visualizations
# ==============================================================================

function(input, output, session) {
  
  # ==========================================================================
  # 1. REACTIVE DATA PROCESSING
  # ==========================================================================
  
  # Create reactive data frame that responds to filter changes
  # This is the CORE REACTIVE EXPRESSION that all outputs depend on
  # It implements SLICING (filter_provinsi, filter_komoditas) and 
  # DICING (filter_tahun, filter_bulan)
  
  filtered_data <- reactive({
    # Trigger on apply button click or filter changes
    input$btn_apply_filter
    
    # Validate inputs
    prov <- input$filter_provinsi
    komodi <- input$filter_komoditas
    tahun_range <- input$filter_tahun
    bulan_sel <- input$filter_bulan
    
    # Safety check
    if (is.null(prov) || is.null(komodi) || length(bulan_sel) == 0) {
      return(NULL)
    }
    
    # Execute query with OLAP pushdown
    # [IMPORTANT NOTE: Query Pushdown Strategy]
    # All SLICING (province, komoditas) and DICING (year range, months) 
    # operations are performed at database level BEFORE collect()
    # This ensures only aggregated data is transferred to R memory
    data <- query_supply_resilience(
      prov = prov,
      komoditas = komodi,
      year_range = tahun_range,
      months = as.numeric(bulan_sel)
    )
    
    return(data)
  })
  
  # Reactive: National aggregated metrics
  national_metrics <- reactive({
    input$btn_apply_filter
    komodi <- input$filter_komoditas
    
    metrics <- get_national_metrics(komodi)
    return(metrics)
  })
  
  # Reactive: Top risk provinces
  top_provinces <- reactive({
    input$btn_apply_filter
    komodi <- input$filter_komoditas
    
    top_prov <- get_top_provinces(n = 5, komodi)
    return(top_prov)
  })
  
  # Reactive: Supply-demand gap analysis
  supply_gap <- reactive({
    input$btn_apply_filter
    prov <- input$filter_provinsi
    komodi <- input$filter_komoditas
    
    if (prov == "Nasional") {
      return(NULL)  # Gap analysis only for specific province
    }
    
    gap <- calculate_supply_demand_gap(prov, komodi)
    return(gap)
  })
  
  # Reactive: Supply dependency analysis
  supply_dependency <- reactive({
    input$btn_apply_filter
    komodi <- input$filter_komoditas
    
    dep <- calculate_supply_dependency(komodi = komodi)
    return(dep)
  })
  
  # Reactive: Spatial risk data for choropleth map
  spatial_risk_data <- reactive({
    input$btn_apply_filter
    komodi <- input$filter_komoditas
    
    spatial_data <- join_spatial_risk(komodi)
    return(spatial_data)
  })
  
  # Reactive: Price-disease correlation data
  price_disease_data <- reactive({
    input$btn_apply_filter
    prov <- input$filter_provinsi
    komodi <- input$filter_komoditas
    
    corr_data <- calculate_price_disease_correlation(
      prov = ifelse(prov == "Nasional", NULL, prov),
      komodi
    )
    return(corr_data)
  })
  
  # ==========================================================================
  # 2. TAB 1: EXECUTIVE SUMMARY (THE ALARM)
  # ==========================================================================
  
  # KPI 1: National Supply Risk Index (0-1 scale)
  # [CRITICAL INDICATOR EXPLANATION]
  # supply_risk_index is a normalized metric (0.0 to 1.0) calculated using:
  # 1. Price Gap: (current_price - baseline_price) / baseline_price
  # 2. Health Impact: (total_sick + total_dead) / livestock_population
  # 3. Supply Strain: total_supply_volume / avg_monthly_demand
  # 
  # All three components are MIN-MAX SCALED to [0, 1] before averaging.
  # Result interpretation:
  # - Risk Index ≈ 0.0-0.33: GREEN (Safe/Aman)
  # - Risk Index ≈ 0.33-0.67: ORANGE (Warning/Peringatan)
  # - Risk Index ≈ 0.67-1.0: RED (Danger/Bahaya)
  
  output$kpi_national_risk <- renderText({
    metrics <- national_metrics()
    
    if (is.null(metrics) || nrow(metrics) == 0) {
      return("N/A")
    }
    
    risk_val <- metrics$national_risk_index[1]
    
    # Return risk index as percentage with color coding
    sprintf("%.2f", risk_val)
  })
  
  # KPI 2: National Average Price
  output$kpi_national_price <- renderText({
    metrics <- national_metrics()
    
    if (is.null(metrics) || nrow(metrics) == 0) {
      return("N/A")
    }
    
    price <- metrics$avg_price[1]
    format(price, big.mark = ",", scientific = FALSE)
  })
  
  # KPI 3: Total Disease Reports
  output$kpi_total_sick <- renderText({
    metrics <- national_metrics()
    
    if (is.null(metrics) || nrow(metrics) == 0) {
      return("N/A")
    }
    
    sick <- metrics$total_sick[1]
    format(sick, big.mark = ",", scientific = FALSE)
  })
  
  # KPI 4: Supply Volume
  output$kpi_supply_volume <- renderText({
    metrics <- national_metrics()
    
    if (is.null(metrics) || nrow(metrics) == 0) {
      return("N/A")
    }
    
    volume <- metrics$total_supply_volume[1]
    format(volume, big.mark = ",", scientific = FALSE)
  })
  
  # Chart: Top Risk Provinces (Bar Chart - OLAP Roll-up visualization)
  output$chart_top_provinces <- renderPlotly({
    top_prov <- top_provinces()
    
    if (is.null(top_prov) || nrow(top_prov) == 0) {
      return(plotly_empty())
    }
    
    # [OLAP ROLL-UP OPERATION]
    # Data is grouped by province and aggregated using AVG(supply_risk_index)
    # This demonstrates OLAP aggregation from granular data to provincial level
    
    plot_ly(top_prov, x = ~reorder(nama_provinsi, -avg_risk_index), 
            y = ~avg_risk_index, type = "bar",
            marker = list(
              color = ~avg_risk_index,
              colorscale = "Reds",
              showscale = TRUE,
              colorbar = list(title = "Risk Index")
            )) %>%
      layout(
        title = "Risiko Pasokan Tertinggi",
        xaxis = list(title = "Provinsi"),
        yaxis = list(title = "Rata-rata Risk Index"),
        hovermode = "x unified"
      )
  })
  
  # Table: Top Risk Provinces (Detailed view)
  output$table_top_provinces <- renderTable({
    top_prov <- top_provinces()
    
    if (is.null(top_prov) || nrow(top_prov) == 0) {
      return(data.frame(Message = "Tidak ada data"))
    }
    
    top_prov %>%
      select(nama_provinsi, avg_risk_index, data_points) %>%
      mutate(
        Status = case_when(
          avg_risk_index < 0.33 ~ "✓ Aman",
          avg_risk_index < 0.67 ~ "⚠ Peringatan",
          TRUE ~ "✗ Bahaya"
        )
      ) %>%
      rename(
        "Provinsi" = nama_provinsi,
        "Risk Index" = avg_risk_index,
        "Data Points" = data_points,
        "Status" = Status
      )
  })
  
  # Choropleth Map (Spatial OLAP)
  # [SPATIAL ANALYSIS IMPLEMENTATION]
  # Joins fact_supply_resilience data with shapefile geometry
  # Spatial join key: nama_provinsi (standardized to uppercase)
  # Visualization: Leaflet choropleth with color gradient based on supply_risk_index
  # Hover tooltip: Province name + risk index + disease count
  
  output$choropleth_map <- renderLeaflet({
    spatial_data <- spatial_risk_data()
    
    if (is.null(spatial_data) || nrow(spatial_data) == 0) {
      # If spatial data unavailable, show message
      leaflet() %>%
        setView(lng = 113.92, lat = -2.55, zoom = 4) %>%
        addTiles() %>%
        addControl(
          html = "<div style='padding: 10px; background: white;'>
                    Spatial data not available
                  </div>",
          position = "topright"
        )
    } else {
      # Color palette based on risk index
      pal <- colorNumeric(
        palette = c("#2ecc71", "#f39c12", "#e74c3c"),
        domain = c(0, 1),
        na.color = "#d3d3d3"
      )
      
      # Prepare labels for hover tooltip
      labels <- sprintf(
        "<strong>%s</strong><br/>Risk Index: %.3f<br/>Penyakit: %s ekor",
        spatial_data$nama_provinsi,
        spatial_data$risk_index,
        format(spatial_data$total_sick, big.mark = ",")
      ) %>%
        lapply(htmltools::HTML)
      
      # Render leaflet choropleth
      leaflet(spatial_data) %>%
        addTiles() %>%
        setView(lng = 113.92, lat = -2.55, zoom = 4) %>%
        addPolygons(
          fillColor = ~pal(risk_index),
          weight = 2,
          opacity = 1,
          color = "white",
          dashArray = "3",
          fillOpacity = 0.7,
          highlightOptions = highlightOptions(
            weight = 5,
            color = "#666",
            dashArray = "",
            fillOpacity = 0.9,
            bringToFront = TRUE
          ),
          label = labels,
          popup = labels
        ) %>%
        addLegend(
          pal = pal,
          values = ~risk_index,
          opacity = 0.7,
          title = "Supply Risk Index",
          position = "bottomright"
        )
    }
  })
  
  # Alert: High Supply Dependency
  # [ALERT TRIGGER LOGIC]
  # Triggers when:
  # 1. A single province supplies > 60% of national supply
  # AND
  # 2. That province has supply_risk_index > 0.67 (high risk category)
  
  output$alert_high_dependency <- renderText({
    dep <- supply_dependency()
    top_prov <- top_provinces()
    
    if (is.null(dep) || is.null(top_prov)) {
      return("")
    }
    
    # Check for critical dependency
    high_dep <- dep %>%
      filter(percentage_national > 60)
    
    if (nrow(high_dep) > 0) {
      top_risk <- top_prov %>%
        filter(nama_provinsi %in% high_dep$nama_provinsi)
      
      if (nrow(top_risk) > 0 && top_risk$avg_risk_index[1] > 0.67) {
        return(paste(
          "<strong>⚠️ BAHAYA: Ketergantungan Tinggi pada Provinsi Berisiko!</strong><br/>",
          top_risk$nama_provinsi[1], "menyuplai", 
          round(high_dep$percentage_national[1], 1), "% pasokan nasional",
          "dengan Risk Index:", round(top_risk$avg_risk_index[1], 3),
          "(kategori BAHAYA). Segera cari alternatif pasokan alternatif!"
        ))
      }
    }
    
    return("✓ Status Pasokan: Stabil. Tidak ada ketergantungan kritis terdeteksi.")
  })
  
  # ==========================================================================
  # 3. TAB 2: ANALISIS SEKTOR RIIL
  # ==========================================================================
  
  # Chart: Supply vs Demand Gap (Logistik Level - Ekor)
  output$chart_supply_demand_ekor <- renderPlotly({
    data <- filtered_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(plotly_empty())
    }
    
    # Aggregate by month for visualization
    plot_data <- data %>%
      group_by(tahun, bulan) %>%
      summarise(
        supply = sum(sum_vol_mutasi, na.rm = TRUE),
        demand = sum(avg_permintaan_bulanan, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        period = paste0(tahun, "-", sprintf("%02d", bulan)),
        gap = supply - demand
      )
    
    # Create bullet chart-style visualization
    plot_ly() %>%
      add_trace(
        x = plot_data$period, y = plot_data$supply,
        name = "Supply (Ekor)", type = "bar",
        marker = list(color = "#2ecc71")
      ) %>%
      add_trace(
        x = plot_data$period, y = plot_data$demand,
        name = "Demand (Ekor)", type = "bar",
        marker = list(color = "#e74c3c")
      ) %>%
      layout(
        title = "Supply vs Demand - Level Logistik",
        xaxis = list(title = "Periode"),
        yaxis = list(title = "Volume (Ekor)"),
        barmode = "group",
        hovermode = "x unified"
      )
  })
  
  # Chart: Supply vs Demand Gap (Consumption Level - Kg)
  output$chart_supply_demand_kg <- renderPlotly({
    data <- filtered_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(plotly_empty())
    }
    
    # [GAP ANALYSIS OPERATION]
    # Calculates (Supply - Demand) to identify deficit/surplus
    # Positive gap = surplus (good)
    # Negative gap = deficit (warning)
    
    plot_data <- data %>%
      group_by(tahun, bulan) %>%
      summarise(
        supply_kg = sum(sum_realisasi_karkas, na.rm = TRUE),
        demand_kg = sum(avg_konsumsi_bulanan, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        period = paste0(tahun, "-", sprintf("%02d", bulan)),
        gap_kg = supply_kg - demand_kg
      )
    
    plot_ly() %>%
      add_trace(
        x = plot_data$period, y = plot_data$supply_kg,
        name = "Supply (Kg)", type = "bar",
        marker = list(color = "#3498db")
      ) %>%
      add_trace(
        x = plot_data$period, y = plot_data$demand_kg,
        name = "Demand (Kg)", type = "bar",
        marker = list(color = "#e67e22")
      ) %>%
      layout(
        title = "Supply vs Demand - Level Konsumsi",
        xaxis = list(title = "Periode"),
        yaxis = list(title = "Volume (Kg)"),
        barmode = "group",
        hovermode = "x unified"
      )
  })
  
  # Table: Supply-Demand Gap Summary
  output$table_supply_demand_gap <- renderTable({
    gap <- supply_gap()
    
    if (is.null(gap) || nrow(gap) == 0) {
      return(data.frame(
        Message = "Pilih provinsi tertentu untuk melihat gap analysis"
      ))
    }
    
    gap %>%
      rename(
        "Provinsi" = nama_provinsi,
        "Avg Supply (Ekor)" = avg_volume_supply_ekor,
        "Avg Demand (Ekor)" = avg_demand_ekor,
        "Avg Karkas (Kg)" = avg_karkas_kg,
        "Avg Konsumsi (Kg)" = avg_consumption_kg,
        "Gap Ekor" = gap_ekor,
        "Gap Kg" = gap_kg
      ) %>%
      mutate(across(where(is.numeric), ~round(., 2)))
  })
  
  # Chart: Supply Dependency (Treemap)
  # [SUPPLY CONCENTRATION ANALYSIS]
  # Visualizes percentage contribution of each province to national supply
  # Larger boxes = higher supply contribution
  # Colors indicate risk level
  
  output$chart_dependency_treemap <- renderPlotly({
    dep <- supply_dependency()
    
    if (is.null(dep) || nrow(dep) == 0) {
      return(plotly_empty())
    }
    
    # Prepare data for treemap
    plot_data <- dep %>%
      mutate(
        risk_category = case_when(
          percentage_national > 60 ~ "Critical (>60%)",
          percentage_national > 40 ~ "High (40-60%)",
          percentage_national > 20 ~ "Medium (20-40%)",
          TRUE ~ "Low (<20%)"
        )
      ) %>%
      arrange(desc(percentage_national)) %>%
      head(10)
    
    plot_ly(
      labels = plot_data$nama_provinsi,
      values = plot_data$percentage_national,
      parents = c(rep("", nrow(plot_data))),
      type = "sunburst",
      marker = list(
        colorscale = "Reds",
        cmid = 30
      )
    ) %>%
      layout(
        title = "Concentration: Kontribusi Provinsi Terhadap Supply Nasional",
        font = list(size = 12)
      )
  })
  
  # Table: Supply Dependency Detail
  output$table_dependency_detail <- renderTable({
    dep <- supply_dependency()
    
    if (is.null(dep) || nrow(dep) == 0) {
      return(data.frame(Message = "Tidak ada data"))
    }
    
    dep %>%
      mutate(
        risk_category = case_when(
          percentage_national > 60 ~ "🔴 KRITIS",
          percentage_national > 40 ~ "🟡 TINGGI",
          percentage_national > 20 ~ "🟡 SEDANG",
          TRUE ~ "🟢 RENDAH"
        )
      ) %>%
      select(nama_provinsi, percentage_national, risk_category) %>%
      arrange(desc(percentage_national)) %>%
      head(10) %>%
      rename(
        "Provinsi" = nama_provinsi,
        "% Supply Nasional" = percentage_national,
        "Risiko" = risk_category
      ) %>%
      mutate(`% Supply Nasional` = round(`% Supply Nasional`, 2))
  })
  
  # Alert: Critical Dependency
  output$alert_critical_dependency <- renderUI({
    dep <- supply_dependency()
    
    if (is.null(dep)) return(NULL)
    
    critical <- dep %>%
      filter(percentage_national > 60)
    
    if (nrow(critical) == 0) {
      return(HTML(
        "<p style='color: #27ae60; font-weight: bold;'>
          ✓ Tidak ada ketergantungan kritis. Supply terdistribusi dengan baik.
        </p>"
      ))
    }
    
    alert_html <- paste0(
      "<div style='padding: 15px; background: #fadbd8; border-left: 4px solid #e74c3c;'>",
      "<p><strong>⚠️ PERINGATAN: Ketergantungan Supply Kritis</strong></p>",
      "<ul>"
    )
    
    for (i in 1:nrow(critical)) {
      alert_html <- paste0(
        alert_html,
        "<li>",
        critical$nama_provinsi[i], " menyuplai ",
        round(critical$percentage_national[i], 1),
        "% dari total pasokan nasional</li>"
      )
    }
    
    alert_html <- paste0(
      alert_html,
      "</ul>",
      "<p><strong>Rekomendasi:</strong> Segera diversifikasi sumber pasokan. ",
      "Jika provinsi utama mengalami gangguan (wabah, bencana), ",
      "pasokan nasional akan terancam serius.</p>",
      "</div>"
    )
    
    HTML(alert_html)
  })
  
  # ==========================================================================
  # 4. TAB 3: INVESTIGASI & KORELASI
  # ==========================================================================
  
  # Chart: Price vs Disease Time Series (Dual-Axis)
  # [CORRELATION INVESTIGATION OPERATION]
  # Shows temporal relationship between avg_harga (left axis) 
  # and sum_jumlah_sakit/sum_jumlah_mati (right axis)
  # Used to determine if price anomalies are driven by disease outbreaks
  # or other market factors
  
  output$chart_price_disease_timeseries <- renderPlotly({
    data <- price_disease_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(plotly_empty())
    }
    
    # Aggregate by month
    ts_data <- data %>%
      group_by(tahun, bulan) %>%
      summarise(
        avg_harga = mean(avg_price, na.rm = TRUE),
        total_sakit = sum(total_sick, na.rm = TRUE),
        total_mati = sum(total_dead, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      mutate(
        period = paste0(tahun, "-", sprintf("%02d", bulan))
      ) %>%
      arrange(tahun, bulan)
    
    # Dual-axis plot using plotly
    plot_ly() %>%
      add_trace(
        x = ts_data$period, y = ts_data$avg_harga,
        name = "Harga Rata-rata (IDR/kg)",
        type = "scatter", mode = "lines+markers",
        line = list(color = "#e74c3c", width = 3),
        yaxis = "y"
      ) %>%
      add_trace(
        x = ts_data$period, y = ts_data$total_sakit,
        name = "Jumlah Sakit (Ekor)",
        type = "scatter", mode = "lines+markers",
        line = list(color = "#3498db", width = 3, dash = "dash"),
        yaxis = "y2"
      ) %>%
      add_trace(
        x = ts_data$period, y = ts_data$total_mati,
        name = "Jumlah Mati (Ekor)",
        type = "scatter", mode = "lines+markers",
        line = list(color = "#9b59b6", width = 3, dash = "dot"),
        yaxis = "y2"
      ) %>%
      layout(
        title = "Investigasi Kausalitas: Tren Harga vs Wabah Penyakit",
        xaxis = list(title = "Periode (Tahun-Bulan)"),
        yaxis = list(
          title = "Harga Rata-rata (IDR/kg)",
          titlefont = list(color = "#e74c3c"),
          tickfont = list(color = "#e74c3c")
        ),
        yaxis2 = list(
          title = "Jumlah Sakit & Mati (Ekor)",
          titlefont = list(color = "#3498db"),
          tickfont = list(color = "#3498db"),
          overlaying = "y",
          side = "right"
        ),
        hovermode = "x unified",
        plot_bgcolor = "#ecf0f1",
        paper_bgcolor = "white"
      )
  })
  
  # Correlation Coefficient Calculation
  output$corr_coefficient <- renderText({
    data <- price_disease_data()
    
    if (is.null(data) || nrow(data) < 2) {
      return("N/A")
    }
    
    # Calculate Pearson correlation between price and sick count
    corr_val <- cor(
      data$avg_price,
      data$total_sick,
      use = "complete.obs",
      method = "pearson"
    )
    
    sprintf("%.3f", corr_val)
  })
  
  # Correlation Interpretation
  # [CORRELATION EXPLANATION]
  # r > 0.7: Strong positive (harga tinggi saat penyakit banyak - supply failure)
  # r 0.3-0.7: Moderate positive (some relationship)
  # r -0.3 to 0.3: Weak/No relationship (harga naik dari faktor lain)
  # r < -0.3: Negative relationship (price stable despite disease)
  
  output$corr_interpretation <- renderUI({
    data <- price_disease_data()
    
    if (is.null(data) || nrow(data) < 2) {
      return(HTML("<p>Insufficient data for correlation analysis</p>"))
    }
    
    corr_val <- cor(
      data$avg_price,
      data$total_sick,
      use = "complete.obs",
      method = "pearson"
    )
    
    interpretation <- ""
    
    if (is.na(corr_val)) {
      interpretation <- "Korelasi tidak dapat dihitung (data tidak lengkap)"
    } else if (corr_val > 0.7) {
      interpretation <- paste0(
        "<p style='color: #e74c3c;'><strong>Korelasi KUAT POSITIF (r = ", 
        sprintf("%.3f", corr_val),
        ")</strong></p>",
        "<p>Interpretasi: Terjadi korelasi kuat antara jumlah hewan sakit ",
        "dan lonjakan harga. Anomali harga di pasar <strong>kemungkinan besar ",
        "disebabkan oleh kegagalan pasokan akibat wabah</strong> di daerah ",
        "produsen, bukan faktor spekulasi murni.</p>"
      )
    } else if (corr_val > 0.3) {
      interpretation <- paste0(
        "<p style='color: #f39c12;'><strong>Korelasi SEDANG POSITIF (r = ", 
        sprintf("%.3f", corr_val),
        ")</strong></p>",
        "<p>Interpretasi: Terdapat hubungan moderate antara penyakit dan harga. ",
        "Namun, <strong>terdapat faktor-faktor lain yang juga mempengaruhi harga</strong> ",
        "(musiman, spekulasi, dll).</p>"
      )
    } else if (corr_val > -0.3) {
      interpretation <- paste0(
        "<p style='color: #27ae60;'><strong>Korelasi LEMAH (r = ", 
        sprintf("%.3f", corr_val),
        ")</strong></p>",
        "<p>Interpretasi: <strong>Tidak ada hubungan signifikan</strong> antara ",
        "jumlah hewan sakit dan fluktuasi harga. Lonjakan harga kemungkinan ",
        "disebabkan oleh faktor lain seperti musiman atau spekulasi pasar.</p>"
      )
    } else {
      interpretation <- paste0(
        "<p style='color: #8e44ad;'><strong>Korelasi NEGATIF (r = ", 
        sprintf("%.3f", corr_val),
        ")</strong></p>",
        "<p>Interpretasi: <strong>Hubungan berlawanan</strong> antara penyakit dan harga. ",
        "Sistem pasokan tampaknya resilient terhadap shock penyakit.</p>"
      )
    }
    
    HTML(interpretation)
  })
  
  # Scatter Plot: Price vs Disease
  output$chart_price_disease_scatter <- renderPlotly({
    data <- price_disease_data()
    
    if (is.null(data) || nrow(data) < 2) {
      return(plotly_empty())
    }
    
    plot_ly(data, x = ~total_sick, y = ~avg_price,
            mode = "markers",
            type = "scatter",
            marker = list(
              size = 8,
              color = ~total_sick,
              colorscale = "Viridis",
              showscale = TRUE,
              colorbar = list(title = "Sick Count")
            ),
            text = ~paste0("Period: ", tahun, "-", bulan,
                          "<br>Price: IDR ", format(avg_price, big.mark = ","),
                          "<br>Sick: ", total_sick)) %>%
      layout(
        title = "Scatter: Harga vs Penyakit",
        xaxis = list(title = "Jumlah Sakit (Ekor)"),
        yaxis = list(title = "Harga (IDR/kg)"),
        hovermode = "closest"
      )
  })
  
  # Correlation Matrix (All Key Metrics)
  output$chart_correlation_matrix <- renderPlot({
    data <- filtered_data()
    
    if (is.null(data) || nrow(data) < 2) {
      return(NULL)
    }
    
    # Select numeric columns for correlation
    corr_cols <- c(
      "avg_harga", "sum_jumlah_sakit", "sum_jumlah_mati",
      "sum_vol_mutasi", "supply_risk_index", "avg_permintaan_bulanan"
    )
    
    # Calculate correlation matrix
    corr_matrix <- data %>%
      select(all_of(corr_cols)) %>%
      cor(use = "complete.obs", method = "pearson")
    
    # Plot correlation matrix
    corrplot::corrplot(
      corr_matrix,
      method = "color",
      type = "upper",
      order = "hclust",
      tl.cex = 0.8,
      tl.col = "black",
      addCoef.col = "black",
      diag = FALSE,
      title = "Correlation Matrix - Key Metrics"
    )
  })
  
  # Detailed Data Table
  output$table_investigation_detail <- DT::renderDT({
    data <- price_disease_data()
    
    if (is.null(data) || nrow(data) == 0) {
      return(data.frame(Message = "No data available"))
    }
    
    display_data <- data %>%
      arrange(desc(tahun), desc(bulan)) %>%
      select(tahun, bulan, avg_price, total_sick, total_dead) %>%
      rename(
        "Tahun" = tahun,
        "Bulan" = bulan,
        "Harga (IDR/kg)" = avg_price,
        "Sakit (Ekor)" = total_sick,
        "Mati (Ekor)" = total_dead
      ) %>%
      mutate(
        `Harga (IDR/kg)` = round(`Harga (IDR/kg)`, 0),
        `Sakit (Ekor)` = format(`Sakit (Ekor)`, big.mark = ","),
        `Mati (Ekor)` = format(`Mati (Ekor)`, big.mark = ",")
      )
    
    DT::datatable(
      display_data,
      options = list(
        pageLength = 10,
        scrollX = TRUE,
        dom = "ftip"
      ),
      rownames = FALSE
    )
  })
  
  # ==========================================================================
  # 5. DATA EXPORT
  # ==========================================================================
  
  output$download_data <- downloadHandler(
    filename = function() {
      paste0("livestock_intelligence_", Sys.Date(), ".csv")
    },
    content = function(file) {
      data <- filtered_data()
      
      if (is.null(data) || nrow(data) == 0) {
        warning("No data to export")
        return()
      }
      
      write.csv(data, file, row.names = FALSE)
    }
  )
  
  # ==========================================================================
  # 6. HELP MODAL
  # ==========================================================================
  
  observeEvent(input$btn_help, {
    shinyalert(
      title = "Panduan Penggunaan Livestock Intelligence",
      text = HTML("
        <h4>Tab 1: Executive Summary (Alarm)</h4>
        <p>Menampilkan KPI nasional dan identifikasi provinsi dengan risiko pasokan tertinggi. 
        Peta spasial membantu visualisasi kerentanan wilayah berdasarkan densitas penyakit.</p>
        
        <h4>Tab 2: Analisis Sektor Riil</h4>
        <p>Menganalisis kesenjangan antara pasokan (supply) dan kebutuhan (demand). 
        Identifikasi provinsi yang terlalu bergantung pada satu pemasok utama.</p>
        
        <h4>Tab 3: Investigasi & Korelasi</h4>
        <p>Menguji hubungan statistik antara anomali harga dengan outbreak penyakit. 
        Membantu membedakan apakah kenaikan harga karena supply failure atau spekulasi.</p>
        
        <h4>Filter Panel</h4>
        <ul>
          <li><strong>Provinsi:</strong> Pilih \"Nasional\" untuk agregasi seluruh negara, 
              atau provinsi tertentu untuk detail spesifik</li>
          <li><strong>Komoditas:</strong> Analisis Sapi atau Ayam secara terpisah</li>
          <li><strong>Tahun:</strong> Gunakan slider untuk memilih rentang waktu</li>
          <li><strong>Bulan:</strong> Checkbox untuk filter bulan spesifik</li>
        </ul>
      "),
      type = "info",
      closeOnEsc = TRUE,
      closeOnClickOutside = TRUE,
      showConfirmButton = TRUE,
      confirmButtonText = "Tutup"
    )
  })
}
