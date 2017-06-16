"""
RAMSES frontend tests




"""

#-----------------------------------------------------------------------------
# Copyright (c) 2013, yt Development Team.
#
# Distributed under the terms of the Modified BSD License.
#
# The full license is in the file COPYING.txt, distributed with this software.
#-----------------------------------------------------------------------------

from yt.testing import \
    assert_equal, \
    requires_file, \
    units_override_check
from yt.utilities.answer_testing.framework import \
    requires_ds, \
    data_dir_load, \
    PixelizedProjectionValuesTest, \
    FieldValuesTest, \
    create_obj
from yt.frontends.ramses.api import RAMSESDataset
import os
import yt

_fields = ("temperature", "density", "velocity_magnitude",
           ("deposit", "all_density"), ("deposit", "all_count"))

output_00080 = "output_00080/info_00080.txt"
@requires_ds(output_00080)
def test_output_00080():
    ds = data_dir_load(output_00080)
    assert_equal(str(ds), "info_00080")
    dso = [ None, ("sphere", ("max", (0.1, 'unitary')))]
    for dobj_name in dso:
        for field in _fields:
            for axis in [0, 1, 2]:
                for weight_field in [None, "density"]:
                    yield PixelizedProjectionValuesTest(
                        output_00080, axis, field, weight_field,
                        dobj_name)
            yield FieldValuesTest(output_00080, field, dobj_name)
        dobj = create_obj(ds, dobj_name)
        s1 = dobj["ones"].sum()
        s2 = sum(mask.sum() for block, mask in dobj.blocks)
        assert_equal(s1, s2)
    assert_equal(ds.particle_type_counts, {'io': 1090895})

@requires_file(output_00080)
def test_RAMSESDataset():
    assert isinstance(data_dir_load(output_00080), RAMSESDataset)

@requires_file(output_00080)
def test_units_override():
    units_override_check(output_00080)


ramsesNonCosmo = 'DICEGalaxyDisk_nonCosmological/output_00002'
@requires_file(ramsesNonCosmo)
def test_unit_non_cosmo():
    ds = yt.load(os.path.join(ramsesNonCosmo, 'info_00002.txt'))

    expected_raw_time = 0.0299468077820411 # in ramses unit
    assert_equal(ds.current_time.value, expected_raw_time)

    expected_time = 14087886140997.336 # in seconds
    assert_equal(ds.current_time.in_units('s').value, expected_time)

ramses_rt = "ramses_rt_00088/output_00088/info_00088.txt"
@requires_file(ramses_rt)
def test_ramses_rt():
    ds = yt.load(ramses_rt)
    ad = ds.all_data()

    expected_fields = ["Density", "x-velocity", "y-velocity", "z-velocity",
                       "Pres_IR", "Pressure", "Metallicity", "HII", "HeII",
                       "HeIII"]

    for field in expected_fields:
        assert(('ramses', field) in ds.field_list)

        # test that field access works
        ad['ramses', field]

    # test that special derived fields for RT datasets work
    special_fields = [('gas', 'temp_IR')]
    species = ['H_p1', 'He_p1', 'He_p2']
    for specie in species:
        special_fields.extend(
            [('gas', specie+'_fraction'), ('gas', specie+'_density'),
             ('gas', specie+'_mass')])

    for field in special_fields:
        assert(field in ds.derived_field_list)
        ret = ad[field]
