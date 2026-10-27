// Original Orbiter Earth 2006 atmosphere and Delta-glider airfoil equations.
// Copyright (c) Martin Schweiger. Licensed under the MIT License.
#include "Aerodynamics.h"
#include "CoreConstants.h"
#include <algorithm>
#include <cmath>
namespace native {
static double oapiGetInducedDrag(double cl,double A,double eps) { return cl*cl/(PI*A*eps); }
static double oapiGetWaveDrag(double M,double M1,double M2,double M3,double cmax) {
    if(M<M1) return 0; if(M<M2) return cmax*(M-M1)/(M2-M1); if(M<M3) return cmax;
    return cmax*sqrt((M3*M3-1)/(M*M-1));
}
Atmosphere earthAtmosphere(double altitude) {

	double alt = std::max(0.,altitude);
    Atmosphere output; auto *prm=&output;
    if(alt>200000) return output;

	const double g0R = 0.0341643;
	// g0/R, where g0 is gravitational acceleration at sea level,
	// and R is specific gas constant for air

	// convert geometric to geopotential altitude
	const double rad = 6.37101e6;
	alt *= rad/(rad+alt);

	double e, t;

	if (alt > 105e3) {
		prm->T   = 225.66;
		e        = exp (-g0R/225.66*(alt-105e3));
		prm->p   = 0.007454273 * e;
		prm->rho = 1.15082e-7 * e;
	} else if (alt > 47e3) {
		if (alt > 79e3) {
			if (alt > 90e3) {
				prm->T   = (alt-90e3)*4e-3+165.66;
				e        = pow (t = prm->T/165.66, -g0R/4e-3);
				prm->p   = 0.1044559 * e;
				prm->rho = 2.19671e-6 *e / t;
			} else {
				prm->T   = 165.66;
				e        = exp (-g0R/165.66*(alt-79e3));
				prm->p   = 1.009601 * e;
				prm->rho = 2.12319e-5 * e;
			}
		} else {
			if (alt > 53e3) {
				prm->T   = (alt-53e3)*(-4.5e-3)+282.66;
				e        = pow (t = prm->T/282.66, -g0R/(-4.5e-3));
				prm->p   = 58.32623 * e;
				prm->rho = 0.000718878 * e / t;
			} else {
				prm->T   = 282.66;
				e        = exp (-g0R/282.66*(alt-47e3));
				prm->p   = 120.4524 * e;
				prm->rho = 0.00148459 * e;
			}
		}
	} else {
		if (alt > 11e3) {
			if (alt > 25e3) {
				prm->T   = (alt-25e3)*3e-3+216.66;
				e        = pow (t = prm->T/216.66, -g0R/3e-3);
				prm->p   = 2488.726 * e;
				prm->rho = 0.0400179 * e / t;
			} else {
				prm->T   = 216.66;
				e        = exp (-g0R/216.66*(alt-11e3));
				prm->p   = 2.26323e4 * e;
				prm->rho = 0.36392 * e;
			}
		} else {
			prm->T   = alt*(-6.5e-3)+288.16;
			e        = pow (t = prm->T/288.16, -g0R/(-6.5e-3));
			prm->p   = 1.01325e5 * e;
			prm->rho = 1.2250 * e / t;
		}
	}

	return output;

}
void verticalLift(double aoa,double M,double *cl,double *cm,double *cd) {

	const int nabsc = 9;
	static const double AOA[nabsc] = {-180*RAD,-60*RAD,-30*RAD, -2*RAD, 15*RAD,20*RAD,25*RAD,60*RAD,180*RAD};
	static const double CL[nabsc]  = {       0,      0,   -0.4,      0,    0.7,     1,   0.8,     0,      0};
	static const double CM[nabsc]  = {       0,      0,  0.014, 0.0039, -0.006,-0.008,-0.010,     0,      0};
	int i;
	for (i = 0; i < nabsc-1 && AOA[i+1] < aoa; i++);
	if (i < nabsc - 1) {
		double f = (aoa - AOA[i]) / (AOA[i + 1] - AOA[i]);
		*cl = CL[i] + (CL[i + 1] - CL[i]) * f;  // aoa-dependent lift coefficient
		*cm = CM[i] + (CM[i + 1] - CM[i]) * f;  // aoa-dependent moment coefficient
	}
	else {
		*cl = CL[nabsc - 1];
		*cm = CM[nabsc - 1];
	}
	double saoa = sin(aoa);
	double pd = 0.015 + 0.4*saoa*saoa;  // profile drag
	*cd = pd + oapiGetInducedDrag (*cl, 1.5, 0.7) + oapiGetWaveDrag (M, 0.75, 1.0, 1.1, 0.04);
	// profile drag + (lift-)induced drag + transonic/supersonic wave (compressibility) drag

}
void horizontalLift(double beta,double M,double *cl,double *cm,double *cd) {

	int i;
	const int nabsc = 8;
	static const double BETA[nabsc] = {-180*RAD,-135*RAD,-90*RAD,-45*RAD,45*RAD,90*RAD,135*RAD,180*RAD};
	static const double CL[nabsc]   = {       0,    +0.3,      0,   -0.3,  +0.3,     0,   -0.3,      0};
	for (i = 0; i < nabsc-1 && BETA[i+1] < beta; i++);
	if (i < nabsc - 1) {
		*cl = CL[i] + (CL[i + 1] - CL[i]) * (beta - BETA[i]) / (BETA[i + 1] - BETA[i]);
	}
	else {
		*cl = CL[nabsc - 1];
	}
	*cm = 0.0;
	*cd = 0.015 + oapiGetInducedDrag (*cl, 1.5, 0.6) + oapiGetWaveDrag (M, 0.75, 1.0, 1.1, 0.04);

}
}
