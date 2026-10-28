#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "OrbiterWorld.generated.h"
namespace native { class Flight; }
class UProceduralMeshComponent;
class USkyAtmosphereComponent;
class UVolumetricCloudComponent;
class UDirectionalLightComponent;
class USkyLightComponent;
class UMaterialInstanceDynamic;
UCLASS()
class AOrbiterWorld : public AActor {
    GENERATED_BODY()
public:
    AOrbiterWorld();
    virtual void BeginPlay() override;
    void Update(const native::Flight &Flight);
    void SetWeather(int32 Preset);
    int32 Weather() const {return WeatherPreset;}
    FString WeatherName() const;
private:
    UPROPERTY() TObjectPtr<UProceduralMeshComponent> Globe;
    UPROPERTY() TObjectPtr<USkyAtmosphereComponent> Atmosphere;
    UPROPERTY() TObjectPtr<UVolumetricCloudComponent> Clouds;
    UPROPERTY() TObjectPtr<UDirectionalLightComponent> Sun;
    UPROPERTY() TObjectPtr<USkyLightComponent> SkyLight;
    UPROPERTY() TObjectPtr<UMaterialInstanceDynamic> CloudMaterial;
    int32 WeatherPreset=1;
    void BuildGlobe();
};
