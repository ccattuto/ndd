# -*- coding: utf-8 -*-
# Author: Simone Marsili
# License: BSD 3 clause
# pylint: disable=c-extension-no-member
"""Base EntropyEstimator class."""
import abc
import logging

import numpy

from ndd.base_estimator import BaseEstimator
from ndd.exceptions import AlphaError, CardinalityError, CountsError

logger = logging.getLogger(__name__)


class EntropyEstimator(BaseEstimator, abc.ABC):
    """
    Base class for entropy estimators.

    Attributes
    ----------
    estimate_ : float
        Entropy estimate
    err_ : float or None
        A measure of uncertainty in the estimate. None if not available.

    """

    def __init__(self):
        self.estimate_ = None
        self.err_ = None

    def __call__(self, *args, **kwargs):
        """Fit and return the estimated value."""
        return self.fit(*args, **kwargs).estimate_

    @property
    def algorithm(self):
        """Estimator function name."""
        return self.__class__.__name__

    @staticmethod
    def check_alpha(a):
        """Check concentration parameter/#pseudocount.

        Parameters
        ----------
        a : positive number
            Concentration parameter or num. pseudocounts

        Returns
        -------
        a : float64

        Raises
        ------
        AlphaError
            If a is not numeric or negative.

        """
        error_msg = 'alpha must be a positive number (got %r).' % a
        if a is None:
            raise AlphaError(error_msg)
        try:
            a = numpy.float64(a)
        except ValueError:
            raise AlphaError(error_msg)
        if a < 0:
            raise AlphaError(error_msg)
        return a

    @staticmethod
    def check_pk(a):
        """
        Raises
        ------
        CountsError
            If pk is not a valid array of counts.

        """

        a = numpy.float64(a).flatten()
        not_integers = not numpy.all([x.is_integer() for x in a])
        negative = numpy.any([a < 0])
        if not_integers:
            raise CountsError('counts array has non-integer values')
        if negative:
            raise CountsError('counts array has negative values')
        return numpy.int32(a)

    @staticmethod
    def check_k(k):
        """
        if k is an integer, just check
        if an array set k = prod(k)
        if None, return

        Raises
        ------
        CardinalityError
            If k is not valid (wrong type, negative, too large...)

        """
        MAX_LOGK = 150 * numpy.log(2)

        if k is None:
            return k
        try:
            k = numpy.float64(k)
        except ValueError:
            raise CardinalityError('%r is not a valid cardinality' % k)
        if k.ndim:
            # if k is a sequence, set k = prod(k)
            if k.ndim > 1:
                raise CardinalityError('k must be a scalar or 1D array')
            logk = numpy.sum(numpy.log(x) for x in k)
            if logk > MAX_LOGK:
                # too large a number; backoff to n_bins?
                # TODO: log warning
                raise CardinalityError('k must be smaller than 2^150 ')
            k = numpy.prod(k)
        else:
            # if a scalar check size
            if numpy.log(k) > MAX_LOGK:
                raise CardinalityError('k must be smaller than 2^150 ')
        if not k.is_integer():
            raise CardinalityError('k must be a whole number (got %r).' % k)

        return k

    def fit(self, pk, k=None):
        """
        Compute an entropy estimate from pk.

        Parameters
        ----------
        pk : array_like, shape (n_bins,)
            The number of occurrences of a set of bins.
        k : int, optional
            Number of bins. k >= len(pk).
            Float values are valid input for whole numbers (e.g. k=1.e3).
            Defaults to len(pk).

        Returns
        -------
        self : object
            Returns the instance itself.

        """
        pk = self.check_pk(pk)
        k = self.check_k(k)

        estimate = self.estimator(pk, k)
        try:
            self.estimate_, self.err_ = estimate
        except TypeError:
            self.estimate_ = estimate

        return self

    @abc.abstractmethod
    def estimator(self, pk, k):
        """Entropy estimator function.

        Return an entropy estimate given counts and the sample space size.

        Parameters
        ----------
        pk : array-like
            An array of non-negative integers (counts array).
        k  : int or sequence or None
            Size of the sample space.
            Float values are valid input for whole numbers (e.g. k=1.e3).
            If a sequence, set k = numpy.prod(k).

        Returns
        -------
        estimate : float
            Entropy estimate
        err : float or None
            A measure of uncertainty in the estimate. None if not available.

        """


class MultiPMFEstimator(EntropyEstimator, abc.ABC):
    """Base class for estimators of entropy-derived funcs from multiple PMF."""

    def __init__(self, entropy_estimator):
        super().__init__()
        self._entropy_estimator = entropy_estimator

    @property
    def entropy_estimator(self):
        """EntropyEstimator object."""
        return self._entropy_estimator

    @entropy_estimator.setter
    def entropy_estimator(self, obj):
        """Entropy estimator setter."""
        if isinstance(obj, EntropyEstimator):
            self._entropy_estimator = obj
        else:
            raise TypeError('Not a EntropyEstimator object.')

    @property
    def algorithm(self):
        """Estimator function name."""
        return self.entropy_estimator.__class__.__name__

    @staticmethod
    def check_pk(a):
        """
        Raises
        ------
        CountsError
            If pk is not a valid array of counts.

        """

        a = numpy.float64(a)
        not_integers = not numpy.all([x.is_integer() for x in a.flatten()])
        negative = numpy.any([a < 0])
        if len(a.shape) != 2:
            raise CountsError('counts array must be 2D.')
        if not_integers:
            raise CountsError('counts array has non-integer values')
        if negative:
            raise CountsError('counts array has negative values')
        return numpy.int32(a)

    def fit(self, pk, k=None):
        """
        Attributes
        ----------
        pk : array_like
            n-by-p array. Different rows correspond to counts from different
            distributions with the same discrete sample space.

        k : int, optional
            Number of bins. k >= p if pk is n-by-p.
            Float values are valid input for whole numbers (e.g. k=1.e3).
            Defaults to pk.shape[1].

        Returns
        -------
        self : object
            Returns the instance itself.

        Raises
        ------
        CountsError
            If pk is not a 2D array.

        """
        pk = self.check_pk(pk)
        k = self.check_k(k)

        estimate = self.estimator(pk, k)
        try:
            self.estimate_, self.err_ = estimate
        except TypeError:
            self.estimate_ = estimate

        return self

    @abc.abstractmethod
    def estimator(self, pk, k):
        """Entropy estimator function.

        Return an entropy estimate given counts and the sample space size.

        Parameters
        ----------
        pk : array-like
            An array of non-negative integers (counts array).
        k  : int or sequence or None
            Size of the sample space.
            Float values are valid input for whole numbers (e.g. k=1.e3).
            If a sequence, set k = numpy.prod(k).

        Returns
        -------
        estimate : float
            Entropy estimate
        err : float or None
            A measure of uncertainty in the estimate. None if not available.

        """
