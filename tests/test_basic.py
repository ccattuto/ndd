# -*- coding: utf-8 -*-
# pylint: disable=missing-docstring
# pylint: disable=redefined-outer-name
"""Tests module."""
import json
import os

import numpy
import numpy.random as random
import pytest

import ndd
import ndd.estimators
from make_test_ref import SEED, cases


def tests_dir():
    """Return None if no tests dir."""
    cwd = os.getcwd()
    basename = os.path.basename(cwd)
    if basename == 'tests':
        return cwd
    tdir = os.path.join(cwd, 'tests')
    if os.path.exists(tdir):
        return tdir
    return None


def random_ndarray(n, p, seed):
    """Random array of characters from ascii_uppercase."""
    import string
    random.seed(seed)
    alphabet = list(string.ascii_uppercase)
    return random.choice(alphabet, size=(n, p))


def random_tuple_generator(n, p, seed):
    import string
    random.seed(seed)
    alphabet = list(string.ascii_uppercase)
    for _ in range(n):
        yield tuple(random.choice(alphabet, size=p))


@pytest.fixture
def data_with_redundancy():
    # generate a dataset with common-cause structure
    random.seed(SEED)
    rnd = lambda x: numpy.random.binomial(n=1, p=x)
    data = []
    for _ in range(1000):
        clouds = rnd(0.2)
        rain = clouds * rnd(0.7) + (1 - clouds) * rnd(0.2)
        dark = clouds * rnd(0.9)
        data.append([clouds, rain, dark])
    return ndd.data.DataArray(numpy.array(data))


with open(os.path.join(tests_dir(), 'data.json'), 'r') as _jf:
    results = json.load(_jf)


@pytest.mark.parametrize('case, ref_result', zip(cases(), results))
def test_entropy(case, ref_result, capsys):
    """Basic tests."""
    import sys
    counts, _, kwargs = case
    test_result = ndd.entropy(counts, k=len(counts), **kwargs)
    out, err = capsys.readouterr()
    sys.stdout.write(out)
    sys.stderr.write(err)
    assert numpy.isclose(test_result, ref_result)


def test_histogram_ndarray():
    N, P = 100, 3
    data = ndd.data.DataArray(random_ndarray(N, P, SEED))
    ref_result = 9.107550241712808
    counts, k = data.iter_counts()
    estimate = ndd.entropy(counts, k=k)
    assert numpy.isclose(estimate, ref_result)  # pylint: disable=protected-access


def test_from_data():
    N, P = 100, 3
    data = random_ndarray(N, P, SEED)
    ref_result = 9.107550241712808
    assert numpy.isclose(
        ndd.nsb.from_data(data),  # pylint: disable=protected-access
        ref_result)


def test_combinations_from_data():
    N, P = 100, 3
    data = random_ndarray(N, P, SEED)
    hs_pairs = ndd.nsb.from_data(data, r=2)  # pylint: disable=protected-access
    ref_result = 18.847999689904068
    assert numpy.isclose(sum(hs_pairs), ref_result)


def test_KLD():
    ALPHA, N, P = 1.0, 100, 20
    random.seed(SEED)
    qk = random.dirichlet([ALPHA] * P)
    pk = random.multinomial(N, qk)
    estimator = ndd.kullback_leibler_divergence
    ref_result = -0.04070168209104397
    assert numpy.isclose(estimator(pk, qk), ref_result)


def test_JSD():
    ALPHA, N, P = 1.0, 100, 20
    random.seed(SEED)
    pk = random.dirichlet([ALPHA] * P)
    counts = random.multinomial(N, pk, size=4)
    estimator = ndd.divergence.JSDivergence()
    ref_result = -0.017281201076104313
    assert numpy.isclose(estimator(counts), ref_result)


def test_mi(data_with_redundancy):
    random.seed(SEED)
    from ndd.nsb import mutual_information
    h1 = ndd.from_data(data_with_redundancy[1])
    h2 = ndd.from_data(data_with_redundancy[2])
    h12 = ndd.from_data(data_with_redundancy[[1, 2]])
    mi = h1 + h2 - h12
    estimate = mutual_information(data_with_redundancy[[1, 2]])
    assert numpy.isclose(estimate, mi)


def test_mmi(data_with_redundancy):
    random.seed(SEED)
    from ndd.nsb import interaction_information
    h0 = ndd.from_data(data_with_redundancy[0], ks=[3])
    h1 = ndd.from_data(data_with_redundancy[1], ks=[3])
    h2 = ndd.from_data(data_with_redundancy[2], ks=[3])
    h01 = ndd.from_data(data_with_redundancy[[0, 1]], ks=[3] * 2)
    h02 = ndd.from_data(data_with_redundancy[[0, 2]], ks=[3] * 2)
    h12 = ndd.from_data(data_with_redundancy[[1, 2]], ks=[3] * 2)
    h012 = ndd.from_data(data_with_redundancy, ks=[3] * 3)
    mmi = -(h0 + h1 + h2 - h01 - h02 - h12 + h012)
    estimate = interaction_information(data_with_redundancy, ks=[3] * 3)
    assert numpy.isclose(estimate, mmi, atol=0.01)


def test_conditional_entropy(data_with_redundancy):
    random.seed(SEED)
    from ndd.nsb import mutual_information
    data = data_with_redundancy[[1, 2]]
    estimate = (ndd.from_data(data) - ndd.conditional_entropy(data, c=0) -
                ndd.conditional_entropy(data, c=1))
    assert numpy.isclose(estimate, mutual_information(data), atol=0.01)


def test_xor():
    random.seed(SEED)

    def xor():
        x, y = numpy.random.randint(2, size=2)
        z = int(x != y)
        return x, y, z

    data = numpy.array([xor() for k in range(500)])
    estimate = ndd.conditional_entropy(data, c=[0, 1])
    assert numpy.isclose(estimate, 0, atol=0.01)
