#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/GameModeBase.h"
#include "GameFramework/HUD.h"
#include "OrbiterPawn.generated.h"
class UProceduralMeshComponent;
class UCameraComponent;
class UMaterialInterface;
class UTexture2D;
class AOrbiterWorld;
struct FOrbiterSimulation;
struct FOrbiterSimulationDeleter { void operator()(FOrbiterSimulation *Value) const; };
UCLASS()
class AOrbiterPawn : public APawn {
    GENERATED_BODY()
public:
    AOrbiterPawn();
    virtual ~AOrbiterPawn() override;
    virtual void BeginPlay() override;
    virtual void Tick(float DeltaSeconds) override;
    FString Readout() const;
private:
    TUniquePtr<FOrbiterSimulation,FOrbiterSimulationDeleter> Sim;
    UPROPERTY() TObjectPtr<UCameraComponent> Camera;
    UPROPERTY() TArray<TObjectPtr<UProceduralMeshComponent>> ShipGroups;
    UPROPERTY() TArray<TObjectPtr<UTexture2D>> Textures;
    UPROPERTY() TArray<TObjectPtr<UMaterialInterface>> Materials;
    UPROPERTY() TObjectPtr<AOrbiterWorld> Earth;
    float CameraYaw=-25,CameraPitch=17,CameraDistance=4300;
    FString Error,CapturePath;
    int32 SmokeFrames=0,Frames=0;
    void LoadFlight(bool Surface);
    void BuildShip();
    void UpdateVisuals();
};
UCLASS()
class AOrbiterHUD : public AHUD {
    GENERATED_BODY()
public:
    virtual void DrawHUD() override;
};
UCLASS()
class AOrbiterGameMode : public AGameModeBase {
    GENERATED_BODY()
public:
    AOrbiterGameMode();
};
