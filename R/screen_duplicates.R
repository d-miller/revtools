screen_duplicates <- function(x){

  input_data <- list(
    raw = NULL,
    columns = NULL,
    grouped = NULL
  )

  if(missing(x)){
    x <- NULL
  }

  if(!is.null(x)){

    # throw a warning if a known file type isn't given
    accepted_inputs <- c("bibliography", "data.frame")
    if(any(accepted_inputs == class(x)) == FALSE){
      stop("only classes 'bibliography' or 'data.frame' accepted by screen_duplicates")}

    switch(class(x),
      "bibliography" = {x <- as.data.frame(x)},
      "data.frame" = {x <- x}
    )
    input_data$columns <- colnames(x)

  }
  input_data$raw <- x

  # create ui
  ui_data <- screen_duplicates_ui()
  ui <- shinydashboard::dashboardPage(
    title = "revtools | screen_duplicates",
  	ui_data$header,
  	ui_data$sidebar,
  	ui_data$body,
  	skin = "black"
  )

  # start server
  server <- function(input, output, session){

    # BUILD REACTIVE VALUES
    data <- reactiveValues(
      raw = input_data$raw,
      columns = input_data$columns,
      grouped = NULL
    )

    display <- reactiveValues(
      data_present = FALSE,
      columns = input_data$columns
    )

    progress <- reactiveValues(
      entry = NULL
    )

    # CREATE HEADER IMAGE
    output$header <- renderPlot({
      revtools_logo(text = "screen_duplicates")
    })

    # DATA INPUT
    observeEvent(input$data_in, {
      if(is.null(data$raw)){
        data_in <- x
      }else{
        data_in <- data$raw
      }
      import_result <- import_shiny(
        source = input$data_in,
        current_data = data_in
      )
      # ensure rownames are unique
      if(any(colnames(import_result) == "label")){
        import_result$label <- make.unique(
          names = import_result$label,
          sep = "_"
        )
      }else{
        import_result$label <- paste0(
          "v",
          seq_len(nrow(import_result))
        )
      }
      # save in reactiveValues
      data$raw <- import_result
      data$columns <- colnames(import_result)
      display$columns <- data$columns

    })

    output$data_selector <- renderUI({
      if(!is.null(data$raw)){
        selectInput(
          inputId = "duplicates_present",
          label = "Is there a variable describing duplicates in this dataset?",
          choices = c("No", "Yes")
        )
      }
    })

    # update ui
    observeEvent(input$duplicates_present, {
      if(input$duplicates_present == "Yes"){
        display$data_present <- TRUE
      }else{
        display$data_present <- FALSE
      }
    })

    # select matching variable(s)
    # i.e. matches are searched for in these columns
    output$response_selector <- renderUI({
      if(!is.null(data$columns)){
        if(display$data_present){
          if(any(data$columns == "matches")){
            selected <- "matches"
          }else{
            selected <- data$columns[1]
          }
          shiny::tagList(
            selectInput(
              inputId = "match_columns",
              label = "Select column containing duplicate data",
              choices = data$columns,
              selected = selected
            ),
            actionButton(
              inputId = "go_duplicates",
              label = "Select",
              width = "85%"
            )
          )
        }else{
          if(any(data$columns == "title")){
            selected <- "title"
          }else{
            selected <- data$columns[1]
          }
          selectInput(
            inputId = "response_selector_result",
            label = "Select column to search for duplicates",
            choices = data$columns,
            selected = selected
          )
        }
      }
    })

    # select grouping variable(s)
    # i.e. possible matches can only be found in subsets defined by these columns
    output$group_selector <- renderUI({
      if(!is.null(data$columns) & !display$data_present){
        lookup <- data$columns %in% c("nsf_proj") #c("journal", "year")
        if(any(lookup)){
          selected <- data$columns[which(lookup)]
        }else{
          data$columns[1] # unclear that this is a good idea
        }
        checkboxGroupInput(
          inputId = "group_selector_result",
          label = "Select grouping variable(s)",
          choices = data$columns,
          selected = selected
        )
      }
    })

    # select display variables
    output$display_selector <- renderUI({
      if(!is.null(data$columns)){
        checkboxGroupInput(
          inputId = "display_result",
          label = "Select variables to display",
          choices = data$columns,
          selected = data$columns
        )
      }
    })

    observeEvent(input$display_result, {
      display$columns <- input$display_result
    })


    # decide which method to use to calculate string distances
    observe({
      output$algorithm_selector <- renderUI({
        if(input$match_function == "fuzzdist"){
          algorithm_list <- list(
            "M Ratio" = "fuzz_m_ratio",
            "Partial Ratio" = "fuzz_partial_ratio",
            "Token Sort Ratio" = "fuzz_token_sort_ratio",
            "Token Set Ratio" = "fuzz_token_set_ratio"
          )
        }else{
          algorithm_list <- c(
            "osa", "lv", "dl",
            "hamming", "lcs",
            "qgram", "cosine",
            "jaccard", "jw", "soundex"
          )
        }
        if(input$match_function != "exact"){
          selectInput(
            inputId = "match_algorithm",
            label = "Select method",
            choices = algorithm_list
          )
        }
      })
    })

    # set a string distance as appropriate for each method
    observe({
      output$threshold_selector <- renderUI({
        if(input$match_function == "fuzzdist"){
          max_val <- 1
          initial_val <- 0.1
          step_val <- 0.05
        }else{
          max_val <- 20
          initial_val <- 5
          step_val <- 1
        }
        if(input$match_function != "exact"){
          sliderInput(
            inputId = "match_threshold",
            label = "Select maximum distance",
            min = 0,
            max = max_val,
            value = initial_val,
            step = step_val
          )
        }
      })
    })

    # If duplicates have already been calculated, load them
    observeEvent(input$go_duplicates, {
      data$raw$matches <- data$raw[, input$match_columns]

      # work out which duplicates to show
      group_result <- split(data$raw, data$raw$matches)
      group_result <- group_result[
        which(unlist(lapply(group_result, nrow)) > 1)
      ]
      if(length(group_result) > 0){
        progress$entry <- 1
        data$grouped <- group_result
      }else{
        progress$entry <- NULL
      }

    })

    # Calculate duplicates
    observeEvent(input$calculate_duplicates, {

      if(length(input$response_selector_result) < 1 & length(input$group_selector_result) < 1){
        if(length(input$response_selector_result) < 1){
          error_modal("Please select a variable to match records by<br><br>
            <em>Click anywhere to exit</em>"
          )
        }else{
          error_modal("Please select 1 or more variables to group records by<br><br>
            <em>Click anywhere to exit</em>"
          )
        }
      }else{
        calculating_modal()
        data$raw$matches <- find_duplicates(
          data = data$raw,
          match_variable = input$response_selector_result,
          group_variables = input$group_selector_result,
          match_function = input$match_function,
          method = input$match_algorithm,
          threshold = input$match_threshold,
          to_lower = input$match_lower,
          remove_punctuation = input$match_punctuation
        )

        # work out which duplicates to show
        group_result <- split(data$raw, data$raw$matches)
        row_counts <- unlist(lapply(group_result, nrow))

        # ensure that every pair of duplicates is shown, even if there are >2 copies
        # i.e. convert groups >2 to many subsets with n = 2
        if(any(row_counts > 2)){
          large_list <- group_result[which(row_counts > 2)]
          cleaned_list <- lapply(large_list, function(a){
            apply(
              combn(nrow(a), 2),
              2,
              function(b, lookup){lookup[as.numeric(b), ]},
              lookup = a
            )
          })
          extracted_list <- do.call(c, cleaned_list)
          if(any(row_counts == 2)){
            group_result <- c(
              group_result[which(row_counts == 2)],
              extracted_list
            )
          }else{
            group_result <- extracted_list
          }
        }else{
          group_result <- group_result[which(row_counts > 1)]
        }

        # if the above finds any duplicates, then proceed
        if(length(group_result) > 0){
          progress$entry <- 1
          data$grouped <- group_result
          removeModal()
        }else{
          progress$entry <- NULL
          removeModal()
          no_duplicates_modal()
        }
      }
    })

    # summary text
    output$match_summary <- renderPrint({
      validate(
        need(data$raw, "Import data to continue")
      )
      if(is.null(data$grouped)){
        cat(
          paste0(
            "<font size='4'>Dataset with ",
            nrow(data$raw),
            " entries</font>"
          )
        )
      }else{
        if(is.null(progress$entry)){
          cat(
            paste0("<font size='4'>Dataset with ",
              nrow(data$raw),
              " entries  |  ",
              length(data$grouped),
              " duplicates remaining</font>"
            )
          )
        }else{
          cat(
            paste0("<font size='4'>Dataset with ",
              nrow(data$raw),
              " entries  |  ",
              length(data$grouped),
              " duplicates remaining</font><br><font size='3'>Showing duplicate #",
              progress$entry,
              "</font>"
            )
          )
        }
      }
    })

    # action buttons
    output$selector_1 <- renderUI({
      if(!is.null(progress$entry)){
        actionButton(
          inputId = "selected_1",
          label = "Select Entry #1",
          width = "100%"
        )
      }
    })
    output$selector_2 <- renderUI({
      if(!is.null(progress$entry)){
        actionButton(
          inputId = "selected_2",
          label = "Select Entry #2",
          width = "100%"
        )
      }
    })
    output$selector_none <- renderUI({
      if(!is.null(progress$entry)){
        actionButton(
          inputId = "selected_none",
          label = "Not duplicates",
          width = "100%",
          style = "background-color: #c17c7c;"
        )
      }
    })
    output$selector_previous <- renderUI({
      if(!is.null(progress$entry)){
        actionButton(
          inputId = "selected_previous",
          label = "Previous",
          width = "100%",
          style = "background-color: #6b6b6b;"
        )
      }
    })
    output$selector_next <- renderUI({
      if(!is.null(progress$entry)){
        actionButton(
          inputId = "selected_next",
          label = "Next",
          width = "100%",
          style = "background-color: #6b6b6b;"
        )
      }
    })

    # text blocks
    output$text_1 <- renderPrint({
      validate(
        need(length(data$grouped) > 0, "")
      )
      format_duplicates(
        x = data$grouped[[progress$entry]][1, ],
        columns = display$columns,
        breaks = input$author_line_breaks
      )
    })
    output$text_2 <- renderPrint({
      validate(
        need(length(data$grouped) > 0, "")
      )
      format_duplicates(
        x = data$grouped[[progress$entry]][2, ],
        columns = display$columns,
        breaks = input$author_line_breaks
      )
    })

    #function to check if the end of duplicates have been reached
    remove_dups = function(remove = NULL) {

      #remove the non-selected entry, but coalesce non-missing information
      if (!is.null(remove)) {
        #get the labels to include and exclude
        label_exclude <- data$grouped[[progress$entry]]$label[remove]
        label_include <- data$grouped[[progress$entry]]$label[3-remove]

        #get the row numbers in the data frame
        rowE <- data$raw$label == label_exclude
        rowI <- data$raw$label == label_include

        #coalesce the rows and remove the excluded rows (requires dplyr package)
        data$raw[rowI, ] <- coalesce(data$raw[rowI, ], data$raw[rowE, ]) 
        data$raw <- data$raw[!rowE, ]

        #remove all the duplicate pairs that have the exclude label
        rmDupPair <- function(pair) label_exclude %in% pair$label
        rmIndexes <- sapply(data$grouped, rmDupPair)
        data$grouped <- data$grouped[!rmIndexes]
      }

      #if the pair is not a duplicate...
      if (is.null(remove)) {

        #change the matches number for the second label in the pair
        label_replace <- data$grouped[[progress$entry]]$label[2]
        row_replace <- data$raw$label == label_replace
        data$raw$matches[row_replace] <- max(data$raw$matches)+1

        #remove only the current duplicate pair
        data$grouped <- data$grouped[-progress$entry]
      }

      #check if the end of duplicates has been reached
      if(progress$entry > length(data$grouped)){
        if(length(data$grouped) == 0){
          progress$entry <- NULL
          save_modal(
            x = data$raw,
            title = "Screening Complete: Save results?"
          )
        }else{
          progress$entry <- length(data$grouped)
        }
      }
    }

    # respond when actionButtons are triggered
    observeEvent(input$selected_1,    { remove_dups(2)    })
    observeEvent(input$selected_2,    { remove_dups(1)    })
    observeEvent(input$selected_none, { remove_dups(NULL) })

    observeEvent(input$selected_previous, {
      if(progress$entry > 1){
        progress$entry <- progress$entry - 1
      }
    })

    observeEvent(input$selected_next, {
      if((progress$entry + 1) <= length(data$grouped)){
        progress$entry <- progress$entry + 1
      }
    })



    # add option to remove data
    observeEvent(input$clear_data, {
      clear_data_modal()
    })

    observeEvent(input$clear_data_confirmed, {
      data$raw <- NULL
      data$columns <- NULL
      data$grouped <- NULL
      progress$entry <- NULL
      removeModal()
    })

    # SAVE OPTIONS
    observeEvent(input$save_data, {
      save_modal(data$raw)
    })

    observeEvent(input$save_data_execute, {
      if(nchar(input$save_filename) == 0){
        filename <- "revtools_data"
      }else{
        if(grepl("\\.[[:lower:]]{3}$", input$save_filename)){
          filename <- substr(
            input$save_filename, 1,
            nchar(input$save_filename) - 4
          )
        }else{
          filename <- input$save_filename
        }
      }
      filename <- paste(filename, input$save_type , sep = ".")
      switch(input$save_type,
        "csv" = {
          write.csv(data$raw,
            file = filename,
            row.names = FALSE
          )
        },
        "rds" = {
          saveRDS(
            data$raw,
            file = filename
          )
        }
      )
      removeModal()
    })

    observeEvent(input$exit_app, {
      exit_modal()
    })

    observeEvent(input$exit_app_confirmed, {
      stopApp(returnValue = invisible(data$raw))
    })

  } # end server

  print(shinyApp(ui, server))

}