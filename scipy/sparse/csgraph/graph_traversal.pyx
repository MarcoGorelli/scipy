"""
Routines for traversing graphs in compressed sparse format
"""

# Author: Jake Vanderplas  -- <vanderplas@astro.washington.edu>
# License: BSD, (C) 2012

import numpy as np
cimport numpy as np

from scipy.sparse import csr_matrix, isspmatrix, isspmatrix_csr, isspmatrix_csc

cimport cython

from libc.stdlib cimport malloc, free

DTYPE = np.float64
ctypedef np.float64_t DTYPE_t

ITYPE = np.int32
ctypedef np.int32_t ITYPE_t

# NULL_IDX is the index used in predecessor matrices to store a non-path
cdef ITYPE_t NULL_IDX = -9999


def cs_graph_breadth_first(csgraph, i_start,
                           directed=True, return_predecessors=True):
    """Return a breadth-first ordering starting with specified node.

    Note that a breadth-first order is not unique, but the tree it
    generates is.

    Parameters
    ----------
    csgraph: array-like or sparse matrix, shape=(N, N)
        compressed sparse graph.  Will be converted to csr format for
        the calculation.
    i_start: integer
        index of starting mode
    directed: bool (default=True)
        if True, then operate on a directed graph: only
        move from point i to point j along paths csgraph[i, j]
        if False, then find the shortest path on an undirected graph: the
        algorithm can progress from point i to j along csgraph[i, j] or
        csgraph[j, i]
    return_predecessors: bool (default=True)
        If True, return the predecesor array

    Returns
    -------
    node_array: np.ndarray, int, shape=(N_nodes,)
        breadth-first list of nodes, starting with specified node
    predecessors: np.ndarray, int, shape=(N_nodes,)
        returned only if return_predecessors == True
        list of predecessors of each node in a breadth-first tree.  If node
        i is in the tree, then its parent is given by predecessors[i].  If
        node i is not in the tree (and for the parent node) then
        predecessors[i] = -9999
    """
    global NULL_IDX

    # if csc matrix and the graph is nondirected, then we can convert to
    # csr using a transpose.
    if (not directed) and isspmatrix_csc(csgraph):
        csgraph = csgraph.T
    elif isspmatrix(csgraph):
        csgraph = csgraph.tocsr()
    else:
        csgraph = csr_matrix(csgraph)

    cdef int N = csgraph.shape[0]
    if csgraph.shape[1] != N:
        raise ValueError("csgraph must be a square matrix")

    cdef np.ndarray node_list = np.empty(N, dtype=ITYPE)
    cdef np.ndarray predecessors = np.empty(N, dtype=ITYPE)
    node_list.fill(NULL_IDX)
    predecessors.fill(NULL_IDX)

    if directed:
        length = _breadth_first(i_start,
                                csgraph.indices, csgraph.indptr,
                                node_list, predecessors)
    else:
        csgraph_T = csgraph.T.tocsr()
        length = _breadth_first_undirected(i_start,
                                           csgraph.indices, csgraph.indptr,
                                           csgraph_T.indices, csgraph_T.indptr,
                                           node_list, predecessors)

    if return_predecessors:
        return node_list[:length], predecessors
    else:
        return node_list[:length]
    

cdef unsigned int _breadth_first(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors):
    # Inputs:
    #  head_node: (input) index of the node from which traversal starts
    #  indices: (input) CSR indices of graph
    #  indptr:  (input) CSR indptr of graph
    #  node_list: (output) breadth-first list of nodes
    #  predecessors: (output) list of predecessors of nodes in breadth-first
    #                tree.  Should be initialized to NULL_IDX
    # Returns:
    #  n_nodes: the number of nodes in the breadth-first tree
    global NULL_IDX

    cdef unsigned int i, pnode, cnode
    cdef unsigned int i_nl, i_nl_end
    cdef unsigned int N = node_list.shape[0]

    node_list[0] = head_node
    i_nl = 0
    i_nl_end = 1

    while i_nl < i_nl_end:
        pnode = node_list[i_nl]

        for i from indptr[pnode] <= i < indptr[pnode + 1]:
            cnode = indices[i]
            if (cnode == head_node):
                continue
            elif (predecessors[cnode] == NULL_IDX):
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                i_nl_end += 1

        i_nl += 1

    return i_nl
    

cdef unsigned int _breadth_first_undirected(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors):
    # Inputs:
    #  head_node: (input) index of the node from which traversal starts
    #  indices1: (input) CSR indices of graph
    #  indptr1:  (input) CSR indptr of graph
    #  indices2: (input) CSR indices of transposed graph
    #  indptr2:  (input) CSR indptr of transposed graph
    #  node_list: (output) breadth-first list of nodes
    #  predecessors: (output) list of predecessors of nodes in breadth-first
    #                tree.  Should be initialized to NULL_IDX
    # Returns:
    #  n_nodes: the number of nodes in the breadth-first tree
    global NULL_IDX

    cdef unsigned int i, pnode, cnode
    cdef unsigned int i_nl, i_nl_end
    cdef unsigned int N = node_list.shape[0]

    node_list[0] = head_node
    i_nl = 0
    i_nl_end = 1

    while i_nl < i_nl_end:
        pnode = node_list[i_nl]

        for i from indptr1[pnode] <= i < indptr1[pnode + 1]:
            cnode = indices1[i]
            if (cnode == head_node):
                continue
            elif (predecessors[cnode] == NULL_IDX):
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                i_nl_end += 1

        for i from indptr2[pnode] <= i < indptr2[pnode + 1]:
            cnode = indices2[i]
            if (cnode == head_node):
                continue
            elif (predecessors[cnode] == NULL_IDX):
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                i_nl_end += 1

        i_nl += 1

    return i_nl





def cs_graph_depth_first(csgraph, i_start,
                           directed=True, return_predecessors=True):
    """Return a depth-first ordering starting with specified node.

    Note that a depth-first order is not unique.  Furthermore, for graphs
    with cycles, the tree generated by a depth-first search is not
    unique either.

    Parameters
    ----------
    csgraph: array-like or sparse matrix, shape=(N, N)
        compressed sparse graph.  Will be converted to csr format for
        the calculation.
    i_start: integer
        index of starting mode
    directed: bool (default=True)
        if True, then operate on a directed graph: only
        move from point i to point j along paths csgraph[i, j]
        if False, then find the shortest path on an undirected graph: the
        algorithm can progress from point i to j along csgraph[i, j] or
        csgraph[j, i]
    return_predecessors: bool (default=True)
        If True, return the predecesor array

    Returns
    -------
    node_array: np.ndarray, int, shape=(N_nodes,)
        breadth-first list of nodes, starting with specified node
    predecessors: np.ndarray, int, shape=(N_nodes,)
        returned only if return_predecessors == True
        list of predecessors of each node in a breadth-first tree.  If node
        i is in the tree, then its parent is given by predecessors[i].  If
        node i is not in the tree (and for the parent node) then
        predecessors[i] = -9999
    """
    global NULL_IDX

    # if csc matrix and the graph is nondirected, then we can convert to
    # csr using a transpose.
    if (not directed) and isspmatrix_csc(csgraph):
        csgraph = csgraph.T
    elif isspmatrix(csgraph):
        csgraph = csgraph.tocsr()
    else:
        csgraph = csr_matrix(csgraph)

    cdef int N = csgraph.shape[0]
    if csgraph.shape[1] != N:
        raise ValueError("csgraph must be a square matrix")

    cdef np.ndarray node_list = np.empty(N, dtype=ITYPE)
    cdef np.ndarray predecessors = np.empty(N, dtype=ITYPE)
    cdef np.ndarray root_list = np.empty(N, dtype=ITYPE)
    cdef np.ndarray flag = np.zeros(N, dtype=int)
    node_list.fill(NULL_IDX)
    predecessors.fill(NULL_IDX)
    root_list.fill(NULL_IDX)

    if directed:
        length = _depth_first(i_start,
                              csgraph.indices, csgraph.indptr,
                              node_list, predecessors,
                              root_list, flag)
    else:
        csgraph_T = csgraph.T.tocsr()
        length = _depth_first_undirected(i_start,
                                         csgraph.indices, csgraph.indptr,
                                         csgraph_T.indices, csgraph_T.indptr,
                                         node_list, predecessors,
                                         root_list, flag)

    if return_predecessors:
        return node_list[:length], predecessors
    else:
        return node_list[:length]
    

cdef unsigned int _depth_first(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] root_list,
                           np.ndarray[int, ndim=1, mode='c'] flag):
    cdef unsigned int i, j, i_nl_end, cnode, pnode
    cdef unsigned int N = node_list.shape[0]
    cdef int no_children, i_root

    node_list[0] = head_node
    root_list[0] = head_node
    i_root = 0
    i_nl_end = 1
    flag[head_node] = 1

    while i_root >= 0:
        print i_root
        pnode = root_list[i_root]
        no_children = True
        for i from indptr[pnode] <= i < indptr[pnode + 1]:
            cnode = indices[i]
            print ' ', pnode, cnode
            if flag[cnode]:
                continue
            else:
                i_root += 1
                root_list[i_root] = cnode
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                flag[cnode] = 1
                i_nl_end += 1
                no_children = False
                break

        if i_nl_end == N:
            break
        
        if no_children:
            i_root -= 1
    
    return i_nl_end
    

cdef unsigned int _depth_first_undirected(
                           unsigned int head_node,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr1,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indices2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] indptr2,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] node_list,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] predecessors,
                           np.ndarray[ITYPE_t, ndim=1, mode='c'] root_list,
                           np.ndarray[int, ndim=1, mode='c'] flag):
    cdef unsigned int i, j, i_nl_end, cnode, pnode
    cdef unsigned int N = node_list.shape[0]
    cdef int no_children, i_root

    node_list[0] = head_node
    root_list[0] = head_node
    i_root = 0
    i_nl_end = 1
    flag[head_node] = 1

    while i_root >= 0:
        print i_root
        pnode = root_list[i_root]
        no_children = True

        for i from indptr1[pnode] <= i < indptr1[pnode + 1]:
            cnode = indices1[i]
            print ' ', pnode, cnode
            if flag[cnode]:
                continue
            else:
                i_root += 1
                root_list[i_root] = cnode
                node_list[i_nl_end] = cnode
                predecessors[cnode] = pnode
                flag[cnode] = 1
                i_nl_end += 1
                no_children = False
                break

        if no_children:
            for i from indptr2[pnode] <= i < indptr2[pnode + 1]:
                cnode = indices2[i]
                print ' ', pnode, cnode
                if flag[cnode]:
                    continue
                else:
                    i_root += 1
                    root_list[i_root] = cnode
                    node_list[i_nl_end] = cnode
                    predecessors[cnode] = pnode
                    flag[cnode] = 1
                    i_nl_end += 1
                    no_children = False
                    break

        if i_nl_end == N:
            break
        
        if no_children:
            i_root -= 1
    
    return i_nl_end

