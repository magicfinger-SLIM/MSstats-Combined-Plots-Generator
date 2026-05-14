# Run this script once before launching the app.

cran_pkgs <- c("shiny", "bslib", "tidyverse", "ggplot2", "patchwork",
               "DT", "TTR", "forcats", "tools")

bioc_pkgs <- c("MSstats", "MSstatsConvert")

missing_cran <- cran_pkgs[!cran_pkgs %in% rownames(installed.packages())]
if (length(missing_cran)) install.packages(missing_cran)

missing_bioc <- bioc_pkgs[!bioc_pkgs %in% rownames(installed.packages())]
if (length(missing_bioc)) {
  if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
  BiocManager::install(missing_bioc)
}

message("All packages ready. Launch with: shiny::runApp()")
