"""
This file contains functions that sample a surface mesh at the point hit by
a ray. These can be used with pyembree in the form of "filter feedback functions."


"""

#-----------------------------------------------------------------------------
# Copyright (c) 2015, yt Development Team.
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------

cimport pyembree.rtcore as rtc
cimport pyembree.rtcore_ray as rtcr
from pyembree.rtcore cimport Vec3f, Triangle, Vertex
from yt.utilities.lib.mesh_construction cimport MeshDataContainer
from yt.utilities.lib.element_mappings cimport \
    ElementSampler, \
    P1Sampler3D, \
    Q1Sampler3D, \
    W1Sampler3D
cimport numpy as np
cimport cython
from libc.math cimport fabs, fmax

cdef ElementSampler Q1Sampler = Q1Sampler3D()
cdef ElementSampler P1Sampler = P1Sampler3D()
cdef ElementSampler W1Sampler = W1Sampler3D()

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void get_hit_position(double* position,
                           void* userPtr,
                           rtcr.RTCRay& ray) nogil:
    cdef int primID, i
    cdef double[3][3] vertex_positions
    cdef Triangle tri
    cdef MeshDataContainer* data

    primID = ray.primID
    data = <MeshDataContainer*> userPtr
    tri = data.indices[primID]

    vertex_positions[0][0] = data.vertices[tri.v0].x
    vertex_positions[0][1] = data.vertices[tri.v0].y
    vertex_positions[0][2] = data.vertices[tri.v0].z

    vertex_positions[1][0] = data.vertices[tri.v1].x
    vertex_positions[1][1] = data.vertices[tri.v1].y
    vertex_positions[1][2] = data.vertices[tri.v1].z

    vertex_positions[2][0] = data.vertices[tri.v2].x
    vertex_positions[2][1] = data.vertices[tri.v2].y
    vertex_positions[2][2] = data.vertices[tri.v2].z

    for i in range(3):
        position[i] = vertex_positions[0][i]*(1.0 - ray.u - ray.v) + \
                      vertex_positions[1][i]*ray.u + \
                      vertex_positions[2][i]*ray.v


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void sample_hex(void* userPtr,
                     rtcr.RTCRay& ray) nogil:
    cdef int ray_id, elem_id, i
    cdef double val
    cdef double[8] field_data
    cdef int[8] element_indices
    cdef double[24] vertices
    cdef double[3] position
    cdef MeshDataContainer* data

    data = <MeshDataContainer*> userPtr
    ray_id = ray.primID
    if ray_id == -1:
        return

    # ray_id records the id number of the hit according to
    # embree, in which the primitives are triangles. Here,
    # we convert this to the element id by dividing by the
    # number of triangles per element.
    elem_id = ray_id / data.tpe

    get_hit_position(position, userPtr, ray)
    
    for i in range(8):
        element_indices[i] = data.element_indices[elem_id*8+i]
        field_data[i]      = data.field_data[elem_id*8+i]

    for i in range(8):
        vertices[i*3]     = data.vertices[element_indices[i]].x
        vertices[i*3 + 1] = data.vertices[element_indices[i]].y
        vertices[i*3 + 2] = data.vertices[element_indices[i]].z    

    # we use ray.time to pass the value of the field
    cdef double mapped_coord[3]
    Q1Sampler.map_real_to_unit(mapped_coord, vertices, position)
    val = Q1Sampler.sample_at_unit_point(mapped_coord, field_data)
    ray.time = val

    # we use ray.instID to pass back whether the ray is near the
    # element boundary or not (used to annotate mesh lines)
    if (fabs(fabs(mapped_coord[0]) - 1.0) < 1e-1 and
        fabs(fabs(mapped_coord[1]) - 1.0) < 1e-1):
        ray.instID = 1
    elif (fabs(fabs(mapped_coord[0]) - 1.0) < 1e-1 and
          fabs(fabs(mapped_coord[2]) - 1.0) < 1e-1):
        ray.instID = 1
    elif (fabs(fabs(mapped_coord[1]) - 1.0) < 1e-1 and
          fabs(fabs(mapped_coord[2]) - 1.0) < 1e-1):
        ray.instID = 1
    else:
        ray.instID = -1

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void sample_wedge(void* userPtr,
                       rtcr.RTCRay& ray) nogil:
    cdef int ray_id, elem_id, i
    cdef double val
    cdef double[6] field_data
    cdef int[6] element_indices
    cdef double[18] vertices
    cdef double[3] position
    cdef MeshDataContainer* data

    data = <MeshDataContainer*> userPtr
    ray_id = ray.primID
    if ray_id == -1:
        return

    # ray_id records the id number of the hit according to
    # embree, in which the primitives are triangles. Here,
    # we convert this to the element id by dividing by the
    # number of triangles per element.
    elem_id = ray_id / data.tpe

    get_hit_position(position, userPtr, ray)
    
    for i in range(6):
        element_indices[i] = data.element_indices[elem_id*6+i]
        field_data[i]      = data.field_data[elem_id*6+i]

    for i in range(6):
        vertices[i*3]     = data.vertices[element_indices[i]].x
        vertices[i*3 + 1] = data.vertices[element_indices[i]].y
        vertices[i*3 + 2] = data.vertices[element_indices[i]].z    

    # we use ray.time to pass the value of the field
    cdef double mapped_coord[3]
    W1Sampler.map_real_to_unit(mapped_coord, vertices, position)
    val = W1Sampler.sample_at_unit_point(mapped_coord, field_data)
    ray.time = val

    cdef double r, s, t
    cdef double thresh = 5.0e-2
    r = mapped_coord[0]
    s = mapped_coord[1]
    t = mapped_coord[2]

    cdef int near_edge_r, near_edge_s, near_edge_t
    near_edge_r = (r < thresh) or (fabs(r + s - 1.0) < thresh)
    near_edge_s = (s < thresh)
    near_edge_t = fabs(fabs(mapped_coord[2]) - 1.0) < thresh
    
    # we use ray.instID to pass back whether the ray is near the
    # element boundary or not (used to annotate mesh lines)
    if (near_edge_r and near_edge_s):
        ray.instID = 1
    elif (near_edge_r and near_edge_t):
        ray.instID = 1
    elif (near_edge_s and near_edge_t):
        ray.instID = 1
    else:
        ray.instID = -1


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void sample_tetra(void* userPtr,
                       rtcr.RTCRay& ray) nogil:

    cdef int ray_id, elem_id, i
    cdef double val
    cdef double[4] field_data
    cdef int[4] element_indices
    cdef double[12] vertices
    cdef double[3] position
    cdef MeshDataContainer* data

    data = <MeshDataContainer*> userPtr
    ray_id = ray.primID
    if ray_id == -1:
        return

    get_hit_position(position, userPtr, ray)

    # ray_id records the id number of the hit according to
    # embree, in which the primitives are triangles. Here,
    # we convert this to the element id by dividing by the
    # number of triangles per element.    
    elem_id = ray_id / data.tpe

    for i in range(4):
        element_indices[i] = data.element_indices[elem_id*4+i]
        field_data[i] = data.field_data[elem_id*4+i]
        vertices[i*3] = data.vertices[element_indices[i]].x
        vertices[i*3 + 1] = data.vertices[element_indices[i]].y
        vertices[i*3 + 2] = data.vertices[element_indices[i]].z    

    # we use ray.time to pass the value of the field
    cdef double mapped_coord[4]
    P1Sampler.map_real_to_unit(mapped_coord, vertices, position)
    val = P1Sampler.sample_at_unit_point(mapped_coord, field_data)
    ray.time = val

    cdef double u, v, w
    cdef double thresh = 2.0e-2
    u = ray.u
    v = ray.v
    w = 1.0 - u - v
    # we use ray.instID to pass back whether the ray is near the
    # element boundary or not (used to annotate mesh lines)
    if ((u < thresh) or 
        (v < thresh) or 
        (w < thresh) or
        (fabs(u - 1) < thresh) or 
        (fabs(v - 1) < thresh) or 
        (fabs(w - 1) < thresh)):
        ray.instID = 1
    else:
        ray.instID = -1


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef void sample_element(void* userPtr,
                         rtcr.RTCRay& ray) nogil:
    cdef int ray_id, elem_id, i
    cdef double val
    cdef MeshDataContainer* data

    data = <MeshDataContainer*> userPtr
    ray_id = ray.primID
    if ray_id == -1:
        return

    # ray_id records the id number of the hit according to
    # embree, in which the primitives are triangles. Here,
    # we convert this to the element id by dividing by the
    # number of triangles per element.
    elem_id = ray_id / data.tpe

    val = data.field_data[elem_id]
    ray.time = val