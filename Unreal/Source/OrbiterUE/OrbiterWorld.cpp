#include "OrbiterWorld.h"
#include "OrbiterCore.h"
#include "ProceduralMeshComponent.h"
#include "Components/SceneComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Components/VolumetricCloudComponent.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyLightComponent.h"
#include "Materials/MaterialInstanceDynamic.h"
static FVector U(const Vector &V){return FVector(V.z,V.x,V.y);}
AOrbiterWorld::AOrbiterWorld() {
    RootComponent=CreateDefaultSubobject<USceneComponent>(TEXT("PlanetCenter"));
    Globe=CreateDefaultSubobject<UProceduralMeshComponent>(TEXT("Earth"));Globe->SetupAttachment(RootComponent);Globe->SetCollisionEnabled(ECollisionEnabled::NoCollision);Globe->SetCanEverAffectNavigation(false);
    Atmosphere=CreateDefaultSubobject<USkyAtmosphereComponent>(TEXT("Atmosphere"));Atmosphere->SetupAttachment(RootComponent);
    Atmosphere->TransformMode=ESkyAtmosphereTransformMode::PlanetCenterAtComponentTransform;Atmosphere->SetBottomRadius(native::EarthRadius/1000);
    Clouds=CreateDefaultSubobject<UVolumetricCloudComponent>(TEXT("WeatherClouds"));Clouds->SetupAttachment(RootComponent);Clouds->SetPlanetRadius(native::EarthRadius/1000);
    Clouds->SetLayerBottomAltitude(1.5);Clouds->SetLayerHeight(4.5);Clouds->SetTracingStartMaxDistance(2000);Clouds->SetTracingMaxDistance(4000);Clouds->SetViewSampleCountScale(1.25);Clouds->SetShadowViewSampleCountScale(.5);
    Sun=CreateDefaultSubobject<UDirectionalLightComponent>(TEXT("Sun"));Sun->SetupAttachment(RootComponent);Sun->SetAtmosphereSunLight(true);Sun->SetIntensity(110000);Sun->bCastCloudShadows=true;Sun->bPerPixelAtmosphereTransmittance=true;Sun->CloudShadowExtent=80;Sun->CloudShadowMapResolutionScale=1;
    Sun->SetWorldRotation((-U(Vector(.32,.84,-.44).unit())).Rotation());
    SkyLight=CreateDefaultSubobject<USkyLightComponent>(TEXT("SkyLight"));SkyLight->SetupAttachment(RootComponent);SkyLight->SetRealTimeCapture(true);SkyLight->CubemapResolution=64;SkyLight->SetIntensity(.5);SkyLight->bLowerHemisphereIsBlack=false;
}
void AOrbiterWorld::BeginPlay() {
    Super::BeginPlay();BuildGlobe();
    if(auto *Base=LoadObject<UMaterialInterface>(nullptr,TEXT("/Engine/EngineSky/VolumetricClouds/m_SimpleVolumetricCloud_Inst.m_SimpleVolumetricCloud_Inst"))) {
        CloudMaterial=UMaterialInstanceDynamic::Create(Base,this);Clouds->SetMaterial(CloudMaterial);
    }
    SetWeather(WeatherPreset);
}
void AOrbiterWorld::BuildGlobe() {
    constexpr int32 Columns=512,Rows=256;
    TArray<FVector> Vertices,Normals;TArray<FVector2D> UV;TArray<int32> Indices;TArray<FLinearColor> Colors;TArray<FProcMeshTangent> Tangents;
    Vertices.Reserve((Columns+1)*(Rows+1));Normals.Reserve(Vertices.Max());UV.Reserve(Vertices.Max());
    for(int32 Y=0;Y<=Rows;++Y)for(int32 X=0;X<=Columns;++X){
        double V=double(Y)/Rows,T=double(X)/Columns,Lat=(.5-V)*Pi,Lon=(T*2-1)*Pi;
        FVector N(cos(Lat)*sin(Lon),cos(Lat)*cos(Lon),sin(Lat));Vertices.Add(N);Normals.Add(N);UV.Add(FVector2D(T,V));
        if(Y<Rows&&X<Columns){int32 A=Y*(Columns+1)+X,B=A+1,C=A+Columns+1,D=C+1;Indices.Append({A,C,B,B,C,D});}
    }
    Globe->CreateMeshSection_LinearColor(0,Vertices,Indices,Normals,UV,Colors,Tangents,false);
    Globe->SetRelativeScale3D(FVector(native::EarthRadius*100));
    if(auto *Material=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/Materials/M_Earth.M_Earth")))Globe->SetMaterial(0,Material);
}
void AOrbiterWorld::Update(const native::Flight &Flight) {
    SetActorLocation(-U(Flight.position)*100);
    // Texture longitude follows the same Earth rotation and obliquity as ground physics.
    auto X=U(native::earthSurface(0,1.5707963267948966,Flight.mjd,Flight.elapsed).up);
    auto Y=U(native::earthSurface(0,0,Flight.mjd,Flight.elapsed).up);
    auto Z=U(native::earthSurface(1.5707963267948966,0,Flight.mjd,Flight.elapsed).up);
    FMatrix Frame=FMatrix::Identity;Frame.SetAxes(&X,&Y,&Z);Globe->SetRelativeRotation(FQuat(Frame));
    SkyLight->SetWorldLocation(FVector::ZeroVector);
}
void AOrbiterWorld::SetWeather(int32 Preset) {
    WeatherPreset=FMath::Clamp(Preset,0,3);Clouds->SetVisibility(WeatherPreset!=0);
    if(!CloudMaterial)return;
    static const float Coverage[]={-1,-.20f,.25f,.48f},Density[]={0,.008f,.014f,.022f};
    CloudMaterial->SetScalarParameterValue(TEXT("Cloud_GlobalCoverage"),Coverage[WeatherPreset]);
    CloudMaterial->SetScalarParameterValue(TEXT("Cloud_GlobalDensity"),Density[WeatherPreset]);
    CloudMaterial->SetScalarParameterValue(TEXT("StormClouds"),WeatherPreset==3?1:0);
    CloudMaterial->SetScalarParameterValue(TEXT("Layout_CloudGlobalScale"),256);
    Clouds->SetLayerBottomAltitude(WeatherPreset==3?.8:1.5);Clouds->SetLayerHeight(WeatherPreset==3?7:4.5);
}
FString AOrbiterWorld::WeatherName() const {static const TCHAR *Names[]={TEXT("Clear"),TEXT("Scattered"),TEXT("Overcast"),TEXT("Storm")};return Names[WeatherPreset];}
