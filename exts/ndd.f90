! Copyright (C) 2016, Simone Marsili 
! All rights reserved.
! License: BSD 3 clause

module constants
  use iso_fortran_env
  implicit none

  real(real64), parameter :: one = 1.0_real64

end module constants

module dirichlet_mod
  use iso_fortran_env
  implicit none

  integer(int32)              :: alphabet_size
  integer(int32)              :: n_data
  integer(int32)              :: n_multi
  integer(int32), allocatable :: multi_z(:)
  integer(int32), allocatable :: multi(:)

contains

  subroutine initialize_dirichlet(counts, nc_)
    ! set alphabet_size, n_data
    ! set n_multi, multi_z, multi
    integer(int32), intent(in) :: counts(:)
    integer(int32), intent(in) :: nc_
    
    alphabet_size = nc_
    n_data = sum(counts)
    
    call compute_multiplicities(counts)
    
  end subroutine initialize_dirichlet

  subroutine compute_multiplicities(counts)
    ! set n_multi, multi_z, multi
    integer(int32), intent(in) :: counts(:)
    integer(int32)              :: nbins
    integer(int32)              :: i_,k_,ni_
    integer(int32)              :: err
    integer(int32)              :: nmax
    integer(int32), allocatable :: multi0(:)

    ! compute multiplicities 
    ! nmax is the largest number of samples in a bin
    nbins = size(counts)
    nmax = maxval(counts)
    allocate(multi0(nmax+1),stat=err)
    ! multi0(n+1) is the number of states with frequency n
    multi0 = 0
    ! take into account the alphabet_size - nbins states with zero frequency
    multi0(1) = alphabet_size - nbins
    do i_ = 1,nbins
       ni_ = counts(i_)
       multi0(ni_ + 1) = multi0(ni_ + 1) + 1
    end do

    ! further compress data into 'sparse' multiplicities
    n_multi = count(multi0 > 0) 
    allocate(multi_z(n_multi),stat=err)
    allocate(multi(n_multi),stat=err)
    k_ = 0
    do i_ = 1, nmax + 1
       if (multi0(i_) > 0) then 
          k_ = k_ + 1
          multi_z(k_) = i_ - 1
          multi(k_) = multi0(i_)
       end if
    end do
    deallocate(multi0)
    
  end subroutine compute_multiplicities

  subroutine dirichlet_finalize()
    
    deallocate(multi_z,multi)
    
  end subroutine dirichlet_finalize

  pure real(real64) function log_pna(alpha) 
    ! log(p(n|a)) (log of) marginal probability of data given alpha
    ! computed from histogram multiplicities. Dirichlet-multinomial.
    use constants
    
    real(real64), intent(in) :: alpha
    integer(int32) :: i_
    real(real64)   :: a(n_multi)

    log_pna = log_gamma(n_data + one) + log_gamma(alpha * alphabet_size) & 
         - alphabet_size * log_gamma(alpha) - log_gamma(n_data + alpha * alphabet_size)
    do i_ = 1, n_multi 
       a(i_) = multi(i_) * (log_gamma(multi_z(i_) + alpha) - log_gamma(multi_z(i_) + one))
    end do
    log_pna = log_pna + sum(a)
    
  end function log_pna

  real(real64) function h_bayes(alpha)
    ! posterior average of the entropy given the data and alpha
    ! computed from histogram multiplicities
    use gamma_funcs, only: digamma
    use constants
    
    real(real64), intent(in) :: alpha
    integer(int32) :: i
    real(real64)   :: a(n_multi)

    h_bayes = 0.0_real64
    do i = 1,n_multi 
       a(i) = multi(i) * (multi_z(i) + alpha) * digamma(multi_z(i) + alpha + one) 
    end do
    h_bayes = - sum(a)
    h_bayes = h_bayes / (n_data + alpha * alphabet_size)
    h_bayes = h_bayes + digamma(n_data + alpha * alphabet_size + one)

  end function h_bayes

  subroutine integrand(alpha, hb, lw)
    ! posterior average of the entropy given the data and alpha
    ! computed from histogram multiplicities
    use gamma_funcs, only: digamma
    use constants
    
    real(real64), intent(in) :: alpha
    real(real64), intent(out) :: hb, lw
    real(real64) :: lpna
    integer(int32) :: mi, mzi
    integer(int32) :: i
    real(real64)   :: a(n_multi),b(n_multi)

    lpna = log_gamma(n_data + one) + log_gamma(alpha * alphabet_size) & 
         - alphabet_size * log_gamma(alpha) - log_gamma(n_data + alpha * alphabet_size)
    do i = 1,n_multi
       mzi = multi_z(i)
       mi = multi(i)
       a(i) = mi * (mzi + alpha) * digamma(mzi + alpha + one)
       b(i) = mi * (log_gamma(mzi + alpha) - log_gamma(mzi + one))
    end do
    hb = - sum(a)
    hb = hb / (n_data + alpha * alphabet_size)
    hb = hb + digamma(n_data + alpha * alphabet_size + one)
    lpna = lpna + sum(b)
    lw = log_fpa(alpha) + lpna

  end subroutine integrand

  elemental real(real64) function log_fpa(a) 
    ! prop. to p(alpha) - the prior for alpha in NSB estimator
    use constants
    use gamma_funcs, only: trigamma
    
    real(real64), intent(in) :: a
    
    log_fpa = log(alphabet_size * trigamma(alphabet_size*a + one) - trigamma(a + one))
    
  end function log_fpa

end module dirichlet_mod

module nsb_mod
  use iso_fortran_env
  implicit none

  real(real64) :: log_alpha1
  real(real64) :: log_alpha2
  real(real64) :: amax
  real(real64) :: lw_max

contains

  elemental real(real64) function log_weight(alpha)
    ! un-normalized weight for alpha in the integrals; prop. to p(alpha|x)
    use dirichlet_mod, only: log_pna, log_fpa

    real(real64), intent(in) :: alpha
    
    log_weight = log_fpa(alpha) + log_pna(alpha)

  end function log_weight

  subroutine compute_integration_range()
    use dirichlet_mod, only: log_pna
    
    integer(int32),parameter :: nx = 100
    real(real64)             :: dx,largest,small_number
    real(real64)             :: xs(nx),fxs(nx)
    real(real64)             :: a1,a2,f,x
    integer(int32)           :: i
    
    largest = huge(dx)
    small_number = 1.0e-30_real64
    log_alpha1 = -20.0_real64
    log_alpha2 = 10.0_real64

    ! initialize amax
    amax = 1.0_real64
    lw_max = log_weight(amax) ! log p(n|a_max)

    ! set intervals equally spaced on log scale
    dx = (log_alpha2 - log_alpha1) / (nx * 1.0_real64)
    do i = 1,nx
       xs(i) = log_alpha1 + (i - 0.5_real64) * dx
    end do
    xs = exp(xs)
    
    fxs = log_weight(xs)
    ! find amax such that the weight in the integral - fwa(alpha) - is maximal
    i = maxloc(fxs,1,fxs < largest)
    amax = xs(i)
    lw_max = log_weight(amax)

    ! recompute fxs
    fxs = exp(log_weight(xs) - lw_max)

    ! re-compute a reasonable integration range
    log_alpha1 = log(minval(xs, fxs > small_number))
    log_alpha2 = log(maxval(xs, fxs > small_number))
    dx = (log_alpha2 - log_alpha1) / (nx * 1.0_real64)
    do i = 1,nx
       xs(i) = log_alpha1 + (i - 0.5_real64) * dx
    end do
    xs = exp(xs)
    
    fxs = log_weight(xs)
    amax = xs(maxloc(fxs,1,fxs < largest))
    lw_max = log_weight(amax)
    
  end subroutine compute_integration_range

  real(real64) function m_func(x)
    use dirichlet_mod, only: h_bayes, integrand

    real(real64), intent(in) :: x
    real(real64) :: a, h_c,lw

    a = exp(x)
    call integrand(a, h_c, lw)
    m_func = exp(lw - lw_max) * h_c * a
    
  end function m_func

  real(real64) function m2_func(x)
    use dirichlet_mod, only: h_bayes, integrand

    real(real64), intent(in) :: x
    real(real64) :: a, h_c,lw

    a = exp(x)
    call integrand(a, h_c, lw)
    m2_func = exp(lw - lw_max) * h_c**2 * a
    
  end function m2_func

  real(real64) function nrm_func(x)

    real(real64), intent(in) :: x
    real(real64) :: a

    a = exp(x)
    nrm_func = exp(log_weight(a) - lw_max)  * a
    
  end function nrm_func

  subroutine hnsb(estimate,err_estimate) 

    real(real64), intent(out) :: estimate,err_estimate
    real(real64)              :: rslt,nrm

    nrm = quad(nrm_func,log_alpha1,log_alpha2)

    estimate = quad(m_func,log_alpha1,log_alpha2)
    estimate = estimate / nrm
    
    err_estimate = quad(m2_func,log_alpha1,log_alpha2)
    err_estimate = err_estimate / nrm
    err_estimate = sqrt(err_estimate - estimate**2)    

  end subroutine hnsb

  real(real64) function quad(func,a1,a2)
    ! wrapper to dqag routine 
    use quadrature, only: dqag

    real(real64),    external :: func
    real(real64),  intent(in) :: a1,a2 
    integer(int32), parameter :: limit = 500
    integer(int32), parameter :: lenw = 4 * limit
    real(real64)              :: abserr
    real(real64),   parameter :: epsabs = 0.0_real64
    real(real64),   parameter :: epsrel = 0.001_real64
    integer(int32)            :: ier
    integer(int32)            :: iwork(limit)
    integer(int32), parameter :: key = 6
    integer(int32)            :: last
    integer(int32)            :: neval
    real(real64),   parameter :: r8_pi = 3.141592653589793_real64
    real(real64)              :: work(lenw)

    call dqag ( func, a1, a2, epsabs, epsrel, key, quad, abserr, neval, ier, &
         limit, lenw, last, iwork, work )
    
  end function quad

end module nsb_mod

subroutine plugin(n,counts,estimate)
  ! plugin estimator - no prior, no regularization 
  use iso_fortran_env
  implicit none

  integer(int32), intent(in) :: n
  integer(int32), intent(in) :: counts(n)
  real(real64),  intent(out) :: estimate

  integer(int32) :: nbins
  integer(int32) :: i
  real(real64)   :: ni,n_data
  integer(int32)              :: mi,nmax,err
  integer(int32), allocatable :: multi0(:)

  ! standard implementation
  nbins = size(counts)
  if (nbins == 1) then 
     estimate = 0.0_real64
     return
  end if
  n_data = sum(counts)*1.0_real64
  estimate = - sum(counts * log(counts*1.0_real64), counts>0)
  estimate = estimate / n_data + log(n_data)
  return 

  ! using multiplicities 
!  nbins = size(counts)
!  if (nbins == 1) then 
!     estimate = 0.0_real64
!     return
!  end if
!  n_data = sum(counts)*1.0_real64
!  nmax = maxval(counts)
!  allocate(multi0(nmax),stat=err)
!  multi0 = 0
!  do i = 1,nbins
!     ni = counts(i)
!     if (ni == 0) cycle
!     multi0(ni) = multi0(ni) + 1
!  end do
!  estimate = 0.0_real64
!  do i = 1,nmax
!     mi = multi0(i)
!     if (mi > 0) estimate = estimate - mi*i*log(i*1.0_real64)
!  end do
!  estimate = estimate / n_data + log(n_data)
!  deallocate(multi0)

end subroutine plugin

subroutine pseudo(n,counts,nc,alpha,estimate)
  use iso_fortran_env
  ! pseudocount estimator(s)
  ! estimate the bin frequencies using pseudocounts 
  ! and then compute the entropy of the regularized histogram 
  ! 
  ! connection to Bayesian modeling with a Dirichlet prior: 
  ! using a Dirichlet prior with parameter alpha, 
  ! the resulting posterior is again Dirichlet with mean corresponding to 
  ! the regularized empirical histogram with alpha as bin pseudocounts
  ! 
  ! the alpha parameter determines the specifical prior: 
  ! 0   : maximum likelihood (ML), or plugin, estimator
  ! 1/2 : Jeffreys' or Krychevsky-Trofimov (KT) estimator
  ! 1   : Laplace (LA) estimator
  ! 1/k : (where k is the number of classes) Schurmann-Grassberger (SG)  estimator
  implicit none

  integer(int32), intent(in)  :: n
  integer(int32), intent(in)  :: counts(n)
  integer(int32), intent(in)  :: nc
  real(real64),   intent(in)  :: alpha
  real(real64),   intent(out) :: estimate

  integer(int32) :: nbins,n_data
  integer(int32) :: i
  real(real64)   :: ni

  if (alpha < 1.0e-10_real64) then
     ! if alpha == 0.0 (no pseudocounts)
     call plugin(n, counts, estimate)
     return
  end if

  nbins = size(counts)
!  if (nbins == 1) then 
!     estimate = 0.0_real64
!     return
!  end if
  n_data = sum(counts)
  estimate = 0.0_real64
  do i = 1,nbins
     ni = counts(i) + alpha
     estimate = estimate - ni*log(ni)
  end do
  ! correct for the (nc - nbins) bins with frequency alpha
  if (nc < nbins) then
     write(0,*) "nddf.pseudo: nclasses cant be < than nbins in the histogram"
     stop
  end if
  if (nc > nbins) estimate = estimate - (nc - nbins)*alpha*log(alpha)
  estimate = estimate / (n_data + nc*alpha) + log(n_data + nc*alpha)

end subroutine pseudo

subroutine dirichlet(n,counts,nc,alpha,estimate)
  ! posterior mean entropy (averaged over Dirichlet distribution) given alpha 
  use iso_fortran_env
  use dirichlet_mod, only: initialize_dirichlet, compute_multiplicities, dirichlet_finalize
  use dirichlet_mod, only: h_bayes
  implicit none

  integer(int32), intent(in)  :: n
  integer(int32), intent(in)  :: counts(n)
  integer(int32), intent(in)  :: nc
  real(real64),   intent(in)  :: alpha
  real(real64),   intent(out) :: estimate

!  if (size(counts) == 1) then 
!     estimate = 0.0_real64
!     return
!  end if

  call initialize_dirichlet(counts, nc)
  call compute_multiplicities(counts)

  estimate = h_bayes(alpha)

  call dirichlet_finalize()

end subroutine dirichlet

subroutine nsb(n,counts,nc,estimate,err_estimate)
  use iso_fortran_env
  use dirichlet_mod, only: initialize_dirichlet, compute_multiplicities, dirichlet_finalize
  use nsb_mod, only: hnsb
  use nsb_mod, only: compute_integration_range
  implicit none

  integer(int32), intent(in)  :: n
  integer(int32), intent(in)  :: counts(n)
  integer(int32), intent(in)  :: nc
  real(real64),   intent(out) :: estimate
  real(real64),   intent(out) :: err_estimate

!  if (size(counts) == 1) then 
!     estimate = 0.0_real64
!     err_estimate = 0.0_real64
!     return
!  end if

  call initialize_dirichlet(counts, nc)
  call compute_multiplicities(counts)

  call compute_integration_range()

  call hnsb(estimate,err_estimate)

  call dirichlet_finalize()

end subroutine nsb

