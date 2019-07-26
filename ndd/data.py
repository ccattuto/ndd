# -*- coding: utf-8 -*-
"""Contains DataArray class."""
import numpy

from ndd.exceptions import DataArrayError


class DataArray(numpy.ndarray):
    """
    Data array helper class.

    Check that input arrays are non-empty 2D arrays.
    """

    def __new__(cls, ar, axis):
        ar = numpy.atleast_2d(ar)

        if not ar.size:
            raise DataArrayError('Empty data array')

        if ar.ndim > 2:
            raise DataArrayError('Input array has %s dimensions; must be 2D' %
                                 ar.ndim)
        if axis == 0:
            ar = ar.T

        ar.flags['WRITEABLE'] = False

        return ar.view(cls)

    def __array_finalize__(self, obj) -> None:
        if obj is None:
            return
        default_attributes = {'_ks': None}
        self.__dict__.update(default_attributes)

    @property
    def ks(self):
        """
        The number of unique elements along axis 0. If data is p-dimensional,
        the num. of unique elements for each variable.
        """
        #  pylint: disable=access-member-before-definition
        #  pylint: disable=attribute-defined-outside-init
        if not self._ks:
            self._ks = numpy.array([len(numpy.unique(v)) for v in self])
        return self._ks
