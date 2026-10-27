#pragma once
namespace native {
struct Atmosphere { double T=0,p=0,rho=0; };
Atmosphere earthAtmosphere(double altitude);
void verticalLift(double aoa,double mach,double *cl,double *cm,double *cd);
void horizontalLift(double beta,double mach,double *cl,double *cm,double *cd);
}
