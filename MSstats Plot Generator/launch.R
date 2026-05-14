# Launch the MSstats HYE Plot Generator Shiny app.
# Run this script from RStudio or the R console.

# Install any missing packages first:
pkgs <- c("shiny", "bslib", "tidyverse", "ggplot2", "patchwork",
          "MSstats", "MSstatsConvert", "TTR")
new  <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(new)) install.packages(new)

shiny::runApp("C:/Claude/MSstats Plot Generator/app.R", launch.browser = TRUE)
