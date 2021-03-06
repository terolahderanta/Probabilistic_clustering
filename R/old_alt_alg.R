#' Full alternating algorithm
#'
#' @param coords Coordinates of the data points.
#' @param weights Weights of the points in a vector.
#' @param k Number of clusters.
#' @param N Number of iterations.
#' @param range Limits for the cluster size in a list.
#' @param capacity_weights Different weights for capacity limits.
#' @param d Distance function used in clustering.
#' @param mu_initialization Method to initialize mu, default is kmpp.
#' @param lambda Outgroup parameter.
#' @param frac_memb Can points be partially allocated?
#' @param place_to_point Place the cluster head in a point?
#' @param fixed_mu Possible fixed center locations.
#' @param gurobi_params A list of parameters for gurobi function e.g. time limit, number of threads.
#'
#' @return Clustering object with allocation, center locations and the value of the objective function
old_alt_alg <- function(coords, weights, k, N = 10, range = as.numeric(bounds(weights, k, radius = 100)),
                    capacity_weights = weights, d = euc_dist2, mu_initialization = NULL, lambda = NULL,
                    frac_memb = FALSE, place_to_point = TRUE, fixed_mu = NULL, gurobi_params = NULL,
                    multip_mu = rep(1, nrow(coords))){
  
  init_mu <- NULL
  print_output <- 1
  
  # Print the information about run
  cat(paste("Progress (N = ", N,"):\n", sep = ""))
  cat(paste("______________________________\n"))
  
  progress_bar <- 0
  
  for (i in 1:N) {
    #if(print_output == 2){
    #  cat(paste("\nLap ", i, "\n-------\n", sep = ""))
    #}
    temp <- prob_clust(data = coords,
                       weights = weights,
                       k = k,
                       prior_dist = "uniform",
                       range = c(range[1], range[2]),
                       capacity_weights = capacity_weights,
                       lambda = lambda,
                       d = d,
                       init_mu = init_mu[[i]],
                       place_to_point = place_to_point,
                       frac_memb = frac_memb,
                       fixed_mu = fixed_mu,
                       gurobi_params = gurobi_params,
                       multip_mu = multip_mu)
    
    if(i == 1){
      min_obj <- temp$obj
      best_temp <- temp
    }
    
    # Print the number of completed laps
    if(print_output == 1 & (floor((i/N)*30) > progress_bar)){
      cat(paste0(rep("#", floor((i/N)*30) - progress_bar), collapse = ""))  
      progress_bar <- floor((i/N)*30)
    } 
    
    # Save the iteration with the lowest value of objective function
    if(temp$obj < min_obj){
      min_obj <- temp$obj
      best_temp <-  temp
    }
  }
  cat("\n")
  return(best_temp)
}

