#' Probabilistic Clustering with Simple Parameters
#'
#' Alternating algorithm for maximizing the joint density. This is a simpler version of
#' the probabilistic clustering algorithm prob_clust, with the constraints to cluster sizes given
#' only as a boundary from L to U.
#'
#' @param data A matrix or data.frame containing the data.
#' @param weights A vector of weights for each data point.
#' @param k The number of clusters.
#' @param init_mu Parameters (locations) that define the k distributions.
#' @param L The lower limit for cluster sizes.
#' @param U The upper limit for cluster sizes.
#' @param capacity_weights Different weights for capacity limits.
#' @param d The distance function.
#' @param fixed_mu Predetermined center locations.
#' @param lambda Outgroup-parameter.
#' @param place_to_point if TRUE, cluster centers will be placed to a point.
#' @param frac_memb If TRUE memberships are fractional.
#' @param gurobi_params A list of parameters for gurobi function e.g. time limit, number of threads.
#' @param dist_mat Distance matrix for all the points. 
#' @return A list containing cluster allocation, cluster center and the current value of the objective function.
#' @keywords internal
prob_clust_gurobi <- function(data, weights, k, init_mu, L, U, capacity_weights = weights, 
                              d = euc_dist2, fixed_mu = NULL, lambda = NULL, place_to_point = TRUE, 
                              frac_memb = FALSE, gurobi_params = NULL, dist_mat = NULL, multip_mu = rep(1, nrow(data))){
  
  # Number of objects in data
  n <- nrow(data)
  
  # Weights must be integers
  weights <- round(weights)
  
  # Initial clusters
  clusters <- rep(0,n)
  
  # Number of fixed centers
  n_fixed <- ifelse(is.null(fixed_mu), 0, nrow(fixed_mu))
  
  if(n_fixed > 0){
    # Cluster centers with fixed centers first
    mu <- rbind(fixed_mu, init_mu[(n_fixed + 1):k,])
  } else {
    # Cluster centers without any fixed centers
    mu <- init_mu
  }
  
  # Maximum number of laps
  max_sim <- 50
  
  for (iter in 1:max_sim) {
    # Old mu is saved to check for convergence
    old_mu <- mu
    
    # Clusters in equally weighted data (Allocation-step)
    temp_allocation <- allocation_gurobi(data = data,
                                         weights = weights,
                                         mu = mu, 
                                         k = k,
                                         L = L,
                                         U = U,
                                         capacity_weights = capacity_weights,
                                         lambda = lambda,
                                         d = d,
                                         frac_memb = frac_memb,
                                         gurobi_params = gurobi_params,
                                         dist_mat = dist_mat,
                                         multip_mu = multip_mu)
    assign_frac <- temp_allocation[[1]]
    obj_max <- temp_allocation[[2]]
    
    # Updating cluster centers (Parameter-step)
    mu <- location_gurobi(data = data,
                          assign_frac = assign_frac,
                          weights = weights,
                          k = k,
                          fixed_mu = fixed_mu,
                          d = d,
                          place_to_point = place_to_point)
    
    #print(paste("Iteration:",iter))
    
    # If nothing is changing, stop
    if(all(old_mu == mu)) break
  }
  
  # Hard clusters from assign_frac
  clusters <- apply(assign_frac, 1, which.max)
  
  # Cluster 99 is the outgroup
  clusters <- ifelse(clusters == (k+1), 99, clusters)
  
  # Return cluster allocation, cluster center and the current value of the objective function
  return(list(clusters = clusters, centers = mu, obj = obj_max, assign_frac = assign_frac))
}

#' Update cluster allocations by maximizing the joint log-likelihood.
#'
#' @param data A matrix or data.frame containing the data, where each object is considered to be equally weighted.
#' @param weights A vector of weights for each data point.
#' @param mu The parameters (locations) that define the k distributions.
#' @param k The number of clusters.
#' @param L The lower limit for cluster sizes.
#' @param U The upper limit for cluster sizes.
#' @param capacity_weights Different weights for capacity limits.
#' @param lambda Outgroup-parameter
#' @param d Distance function.
#' @param frac_memb If TRUE memberships are fractional.
#' @param gurobi_params A list of parameters for gurobi function e.g. time limit, number of threads.
#' @param dist_mat Distance matrix for all the points.
#' @return New cluster allocations for each object in data and the maximum of the objective function.
#' @keywords internal
allocation_gurobi <- function(data, weights, mu, k, L, U, capacity_weights = weights, lambda = NULL,
                              d = euc_dist2, frac_memb = FALSE, gurobi_params = NULL, dist_mat = NULL,
                              multip_mu = rep(1, nrow(data))){
  
  # Number of objects in data
  n <- nrow(data)
  
  # Is there an outgroup cluster
  is_outgroup <- !is.null(lambda)
  
  # Number of decision variables
  if(is_outgroup){
    n_decision <- n * k + n
    
  } else{
    n_decision <- n * k
    
  }
  
  
  if(is.null(dist_mat)){
    C <- matrix(0, ncol = k, nrow = n)
    for(i in 1:k){
      C[,i] <- apply(data, MARGIN = 1, FUN = d, x2 = mu[i,])
    }
  } else {
    C <- dist_mat
  }
  
  # Multiplier for the normalized values
  multip <- 1
  
  # Normalization
  C <- (C - min(C))/(max(C)- min(C))*multip
  weights <- (weights/max(weights))*multip
  
  max_w <- max(capacity_weights)
  capacity_weights <- (capacity_weights/max_w)*multip
  L <- (L/max_w)*multip
  U <- (U/max_w)*multip
  
  # Gurobi-model
  model <- list()
  
  # Constrains 2 and  3
  const23 <- Matrix::spMatrix(nrow = k, ncol = n_decision, 
                      i = rep(1:k, each = n),
                      j = 1:(n*k),
                      x = rep(weights, k))
  
  # Add constraints 1, 2 and 3 to model
  model$A <- rbind(Matrix::spMatrix(nrow = n, ncol = n_decision, 
                            i = rep(1:n, times = ifelse(is_outgroup, k + 1, k)),
                            j = rep(1:n_decision),
                            x = rep(1, n_decision)),
                   const23,
                   const23
  )
  # First constraint
  #const1 <- NULL
  #for (i in 1:n) {
  #  const1 <- c(const1, as.numeric(rep(1:n == i, ifelse(is_outgroup, k + 1, k))))
  #}
  #
  ## Second constraint
  #const2 <- NULL
  #temp <- c(t(matrix(1, ncol = n, nrow = k) * 1:k))
  #for (i in 1:k) {
  #  const2 <- c(const2, as.numeric(temp == i, n)*capacity_weights, rep(0, ifelse(is_outgroup, n, 0)))
  #}
  #
  ## Third constraint
  #const3 <- const2
  #
  ## Gurobi-model
  #model <- list()
  #
  ## Constraint matrix A
  #model$A          <- matrix(c(const1, const2, const3), 
  #                           nrow=n + 2*k, 
  #                           ncol=n_decision, 
  #                           byrow=T)
  
  # Outgroup penalty
  if(is_outgroup){
    nu <- mean(C)
    # With weights:
    obj_fn <- c(c(C * weights), lambda * weights)
    
    # Without weights:
    #obj_fn <- c(c(C * weights), lambda * rep(1,n))
  } else {
    obj_fn <- c(C * weights) 
  }
  
  model$obj        <- obj_fn
  
  model$modelsense <- 'min'
  
  model$rhs        <- c(multip_mu, 
                        rep(L, k), 
                        rep(U, k))
  
  model$sense      <- c(rep('=', n), 
                        rep('>', k), 
                        rep('<', k))
  
  # B = Binary, C = Continuous
  model$vtype      <- ifelse(frac_memb, 'C', 'B')
  
  # Using timelimit-parameter to stop the optimization if time exceeds 10 minutes
  if(is.null(gurobi_params)){
    gurobi_params <- list()
    gurobi_params$TimeLimit <- 600
    gurobi_params$OutputFlag <- 0  
  }
  
  # Solving the linear program
  result <- gurobi::gurobi(model, params = gurobi_params)
  
  # Send error message if the model was infeasible
  if(result$status == "INFEASIBLE") {stop("Model was infeasible!")}
  
  assign_frac <- matrix((result$x), ncol = ifelse(is_outgroup, k + 1, k))
  
  obj_max <- round(result$objval, digits = 3)
  
  # Clear space
  rm(model, result)
  
  return(list(assign_frac,
              obj_max))
}


#' Updates the parameters (centers) for each cluster.
#'
#' @param data A data.frame containing the data points, one per row.
#' @param assign_frac A vector of cluster assignments for each data point.
#' @param weights The weights of the data points
#' @param k The number of clusters.
#' @param fixed_mu Predetermined center locations.
#' @param d The distance function.
#' @param place_to_point if TRUE, cluster centers will be placed to a point.
#' @return New cluster centers.
#' @keywords internal
location_gurobi <- function(data, assign_frac, weights, k, fixed_mu = NULL, d = euc_dist2, place_to_point = TRUE){
  
  # Matrix for cluster centers
  mu <- matrix(0, nrow = k, ncol = ncol(data))
  
  # Number of fixed centers
  n_fixed <- ifelse(is.null(fixed_mu), 0, nrow(fixed_mu))
  
  if(n_fixed > 0){
    # Insert the fixed mu first
    for(i in 1:n_fixed){
      mu[i,] <- fixed_mu[i,]
    }
  }
  
  # Update mu for each cluster
  #for (i in (ifelse(n_fixed > 0, n_fixed + 1, 1)):k) {
  #  
  #  if(place_to_point){
  #    # Compute medoids only with points that are relevant in the cluster i
  #    relevant_cl <- assign_frac[, i] > 0.001
  #    
  #    # Computing medoids for cluster i
  #    #   New weights are combined from assignment fractionals and weights
  #    mu[i,] <- as.matrix(medoid(data = data[relevant_cl,],
  #                               w = assign_frac[relevant_cl, i] * weights[relevant_cl],
  #                               d = d))
  #  } else {
  #    # Weighted mean
  #    mu[i,] <- colSums(data * weights * assign_frac[, i]) / sum(assign_frac[, i]*weights)
  #  }
  #}
  
  #setup parallel backend to use many processors
  cores <- detectCores()
  cl <- makeCluster(cores[1]-1) # not to overload your computer
  registerDoParallel(cl)
  
  # Update mu for each cluster
  if(place_to_point){
    mu <- foreach(i = (ifelse(n_fixed > 0, n_fixed + 1, 1)):k, .combine = rbind) %dopar% {
      # Compute medoids only with points that are relevant in the cluster i
      relevant_cl <- assign_frac[, i] > 0.001
      
      # Computing medoids for cluster i
      #   New weights are combined from assignment fractionals and weights
      temp_mu <- as.matrix(medoid(data = data[relevant_cl,],
                                 w = assign_frac[relevant_cl, i] * weights[relevant_cl],
                                 d = d))
      # rbind the temp_mus
      temp_mu
    }
  } else {
    for (i in (ifelse(n_fixed > 0, n_fixed + 1, 1)):k) {
      # Weighted mean
      mu[i,] <- colSums(data * weights * assign_frac[, i]) / sum(assign_frac[, i] * weights)
    }
  }

  #stop cluster
  stopCluster(cl)
  
  
  return(mu)
}
