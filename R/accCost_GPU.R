#' Accumulated Cost Surface
#' 
#' Calculates the accumulated cost surface from one or 
#'  more origins.
#' 
#' @name accCost_GPU
#' @aliases accCost_GPU
#' @aliases accCost_GPU,TransitionLayer,RasterLayer-method
#' @aliases accCost_GPU,TransitionLayer,Coords-method
#' @keywords spatial
#' 
#' @param x object of class \code{TransitionLayer}
#' @param fromCoords origin point locations (SpatialPoints, matrix 
#'  or numeric class)
#'  
#' @return a RasterLayer object
#' @details 
#' If more than one coordinate is supplied in fromCoords, 
#'  the function calculates the minimum least-cost distance 
#'  from any origin point.
#'  
#' The function uses Dijkstra's algorithm 
#'  (as implemented in the igraph package).
#' @references 
#' E.W. Dijkstra. 1959. A note on two problems 
#'  in connexion with graphs. \emph{Numerische Mathematik} 1, 269 - 271.
#' @author M.G. Mashiku
#' @seealso 
#'  \code{\link{geoCorrection}},
#'  \code{\link{costDistance}}
#' @examples
#' library("raster")
#' # example equivalent to that in the documentation on r.cost in GRASS
#' r <- raster(nrows=6, ncols=7, 
#'             xmn=0, xmx=7, 
#'             ymn=0, ymx=6, 
#'             crs="+proj=utm +units=m")
#' 
#' r[] <- c(2, 2, 1, 1, 5, 5, 5,
#'          2, 2, 8, 8, 5, 2, 1,
#'          7, 1, 1, 8, 2, 2, 2,
#'          8, 7, 8, 8, 8, 8, 5,
#'          8, 8, 1, 1, 5, 3, 9,
#'          8, 1, 1, 2, 5, 3, 9)
#' 
#' # 1/mean: reciprocal to get permeability
#' tr <- par_transition(r, function(x) 1/mean(x), 8) 
#' tr <- geoCorrection(tr)
#' 
#' c1 <- c(5.5,1.5) 
#' c2 <- c(1.5,5.5)
#' 
#' A <- accCost_GPU(tr, c1)
#' plot(A)
#' text(A)
#' @import Matrix
#' @import methods
#' @import raster
#' @importFrom igraph clusters E E<- get.shortest.paths
#'  graph.adjacency shortest.paths
#' @importFrom stats as.dist cov na.omit
#' @importFrom sp coordinates CRS Line Lines SpatialLines
#' @importClassesFrom sp SpatialPoints SpatialPointsDataFrame SpatialPixels
#'  SpatialGrid SpatialPixelsDataFrame SpatialGridDataFrame
#' @exportMethod accCost_GPU
setGeneric("accCost_GPU", function(x, fromCoords){
  standardGeneric("accCost_GPU")
  })

setMethod("accCost_GPU", signature(x = "TransitionLayer", 
                               fromCoords = "Coords"), 
          def = function(x, fromCoords)
{
  fromCoords <- .coordsToMatrix(fromCoords) 
  fromCells <- cellFromXY(x, fromCoords)
  if(!all(!is.na(fromCells))){
    warning("some coordinates not found and omitted")
    fromCells <- fromCells[!is.na(fromCells)]
  }
  tr <- transitionMatrix(x)
  tr <- rbind(tr,rep(0,nrow(tr)))
  tr <- cbind(tr,rep(0,nrow(tr)))
  
  startNode <- nrow(tr) # extra node to serve as origin
  adjP <- cbind(rep(startNode, times=length(fromCells)), fromCells)
  
  tr[adjP] <- Inf
  
  adjacencyGraph_igraph <- graph.adjacency(tr, mode="directed", weighted=TRUE)
  E(adjacencyGraph_igraph)$weight <- 1 / E(adjacencyGraph_igraph)$weight	

  if (require(cuRnet)) {
    print("Library cuRnet was succefully loaded, CUDA and GPU library are on the system.")
    library(cuRnet)

    adjacencyGraph_df <- as_data_frame(adjacencyGraph_igraph)
    colnames(adjacencyGraph_df)[3] <- 'score'
    
    adjacencyGraph <- cuRnet_graph(adjacencyGraph_df)
    shortestPaths <- cuRnet_sssp_dists(adjacencyGraph, 
                                  from=startNode)[-startNode]
            
    #shortestPaths <- cuRnet_sssp_dists(adjacencyGraph, 
                                  #v=startNode, mode="out")[-startNode]
  
    result <- as(x, "RasterLayer")
    result <- setValues(result, shortestPaths)	
    return(result)
  }
}
)

