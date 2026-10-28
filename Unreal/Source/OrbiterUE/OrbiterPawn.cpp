#include "OrbiterPawn.h"
#include "OrbiterWorld.h"
#include "OrbiterExhaust.h"
#if WITH_EDITOR
#include "AssetCompilingManager.h"
#include "ShaderCompiler.h"
#endif
#include "Camera/CameraComponent.h"
#include "Components/SceneComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Components/DirectionalLightComponent.h"
#include "Components/SkyAtmosphereComponent.h"
#include "Engine/DirectionalLight.h"
#include "Engine/StaticMesh.h"
#include "Engine/Texture2D.h"
#include "Engine/Canvas.h"
#include "GameFramework/PlayerController.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Misc/Paths.h"
#include "ProceduralMeshComponent.h"
#include "Engine/World.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "OrbiterCore.h"
#include "UnrealClient.h"
#include "HAL/PlatformMisc.h"
#include "DynamicRHI.h"
struct FOrbiterSimulation { native::Flight Flight; native::Mesh Mesh; FString Data; };
void FOrbiterSimulationDeleter::operator()(FOrbiterSimulation *Value) const {delete Value;}
static FVector U(const Vector &V) {return FVector(V.z,V.x,V.y);}
static FQuat Basis(const FVector &X,const FVector &Y,const FVector &Z) {
    FMatrix M=FMatrix::Identity;M.SetAxes(&X,&Y,&Z);return FQuat(M);
}
AOrbiterPawn::AOrbiterPawn() {
    PrimaryActorTick.bCanEverTick=true;
    RootComponent=CreateDefaultSubobject<USceneComponent>(TEXT("SimulationFrame"));
    Camera=CreateDefaultSubobject<UCameraComponent>(TEXT("FlightCamera"));Camera->SetupAttachment(RootComponent);Camera->SetFieldOfView(65);
    auto &P=Camera->PostProcessSettings;
    P.bOverride_AutoExposureMethod=true;P.AutoExposureMethod=AEM_Manual;
    P.bOverride_AutoExposureApplyPhysicalCameraExposure=true;P.AutoExposureApplyPhysicalCameraExposure=true;
    P.bOverride_CameraISO=true;P.CameraISO=100;P.bOverride_CameraShutterSpeed=true;P.CameraShutterSpeed=125;
    P.bOverride_DepthOfFieldFstop=true;P.DepthOfFieldFstop=16;P.bOverride_AutoExposureBias=true;P.AutoExposureBias=0;
    AutoPossessPlayer=EAutoReceiveInput::Player0;
}
AOrbiterPawn::~AOrbiterPawn()=default;
void AOrbiterPawn::LoadFlight(bool Surface) {
    Sim->Flight.load(TCHAR_TO_UTF8(*(Sim->Data/(Surface?TEXT("Scenarios/Cape Canaveral native.scn"):TEXT("Scenarios/DG Mk4 in orbit.scn")))));
    Error.Empty();
}
void AOrbiterPawn::BeginPlay() {
    Super::BeginPlay();
    FParse::Value(FCommandLine::Get(),TEXT("OrbiterCameraYaw="),CameraYaw);
    FParse::Value(FCommandLine::Get(),TEXT("OrbiterCameraPitch="),CameraPitch);
    FParse::Value(FCommandLine::Get(),TEXT("OrbiterFrames="),SmokeFrames);
    FParse::Value(FCommandLine::Get(),TEXT("OrbiterCapture="),CapturePath);
    try {
        Sim.Reset(new FOrbiterSimulation);Sim->Data=FPaths::ConvertRelativePathToFull(FPaths::ProjectContentDir()/TEXT("OrbiterData"));
        LoadFlight(FParse::Param(FCommandLine::Get(),TEXT("surface")));
        if(FParse::Param(FCommandLine::Get(),TEXT("OrbiterEarthDemo"))) {
            Sim->Flight.placeOnEarth(28.5*RAD,-80.6*RAD,90*RAD,350000);
            Sim->Flight.velocity=native::earthSurface(28.5*RAD,-80.6*RAD,Sim->Flight.mjd).east*sqrt(native::Mu/Sim->Flight.position.length());
            Sim->Flight.align(Sim->Flight.velocity);
            Sim->Flight.glider.part(native::Part::Gear).position=Sim->Flight.glider.part(native::Part::Gear).target=0;
        }
        Sim->Mesh=native::loadMesh(TCHAR_TO_UTF8(*(Sim->Data/TEXT("Meshes/deltaglider_ns.msh"))));BuildShip();
        Exhaust=GetWorld()->SpawnActor<AOrbiterExhaust>();
        FParse::Value(FCommandLine::Get(),TEXT("OrbiterThrust="),Sim->Flight.throttle);
        RcsDemo=FParse::Param(FCommandLine::Get(),TEXT("OrbiterRCS"));
        Earth=GetWorld()->SpawnActor<AOrbiterWorld>();
        int32 Weather=1;FParse::Value(FCommandLine::Get(),TEXT("OrbiterWeather="),Weather);Earth->SetWeather(Weather);
        if(auto *PC=Cast<APlayerController>(GetController()))PC->bShowMouseCursor=true;
        UpdateVisuals();
#if WITH_EDITOR
        FAssetCompilingManager::Get().FinishAllCompilation();
        if(GShaderCompilingManager)GShaderCompilingManager->FinishAllCompilation();
#endif
    }catch(const std::exception &E){Error=UTF8_TO_TCHAR(E.what());UE_LOG(LogTemp,Error,TEXT("Orbiter: %s"),*Error);}
}
void AOrbiterPawn::BuildShip() {
    UMaterialInterface *Base=LoadObject<UMaterialInterface>(nullptr,TEXT("/Game/Materials/M_Orbiter.M_Orbiter"));
    Textures.Add(nullptr);
    for(auto Name:Sim->Mesh.textures) {
        FString Path=UTF8_TO_TCHAR(Name.c_str());Path.ReplaceInline(TEXT("\\"),TEXT("/"));
        auto Image=native::loadDDS(TCHAR_TO_UTF8(*(Sim->Data/TEXT("Textures")/Path)));
        auto *Texture=UTexture2D::CreateTransient(Image.width,Image.height,PF_R8G8B8A8);Texture->SRGB=true;
        void *Bytes=Texture->GetPlatformData()->Mips[0].BulkData.Lock(LOCK_READ_WRITE);FMemory::Memcpy(Bytes,Image.rgba.data(),Image.rgba.size());Texture->GetPlatformData()->Mips[0].BulkData.Unlock();Texture->UpdateResource();Textures.Add(Texture);
    }
    for(const auto &G:Sim->Mesh.groups) {
        auto *Component=NewObject<UProceduralMeshComponent>(this);Component->SetupAttachment(RootComponent);Component->RegisterComponent();Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
        TArray<FVector> Vertices,Normals;TArray<int32> Indices;TArray<FVector2D> UV;TArray<FLinearColor> Colors;TArray<FProcMeshTangent> Tangents;
        for(const auto &V:G.vertices){Vertices.Add(U(Vector(V.x,V.y,V.z))*100);Normals.Add(U(Vector(V.nx,V.ny,V.nz)));UV.Add(FVector2D(V.u,V.v));}
        // Orbiter meshes use the opposite front-face winding to Unreal's mesh factory.
        for(size_t I=0;I+2<G.indices.size();I+=3){Indices.Add(G.indices[I]);Indices.Add(G.indices[I+2]);Indices.Add(G.indices[I+1]);}
        Component->CreateMeshSection_LinearColor(0,Vertices,Indices,Normals,UV,Colors,Tangents,false);
        if(Base) {auto *M=UMaterialInstanceDynamic::Create(Base,this);auto &D=Sim->Mesh.materials[G.material].diffuse;M->SetVectorParameterValue(TEXT("Tint"),FLinearColor(D[0],D[1],D[2],D[3]));if(G.texture)M->SetTextureParameterValue(TEXT("Diffuse"),Textures[G.texture]);Component->SetMaterial(0,M);Materials.Add(M);}
        ShipGroups.Add(Component);
    }
}
void AOrbiterPawn::UpdateVisuals() {
    if(!Sim||!Error.IsEmpty())return;auto &F=Sim->Flight;
    SetActorRotation(Basis(U(F.forward),U(F.right),U(F.up)));
    auto Transforms=F.glider.transforms(ShipGroups.Num());
    for(int32 I=0;I<ShipGroups.Num();++I) {auto &T=Transforms[I];ShipGroups[I]->SetRelativeTransform(FTransform(Basis(U(mul(T.rotation,Vector(0,0,1))),U(mul(T.rotation,Vector(1,0,0))),U(mul(T.rotation,Vector(0,1,0)))),U(T.translation)*100));}
    FVector Offset=FRotator(-CameraPitch,CameraYaw,0).Vector()*-CameraDistance;Camera->SetRelativeLocation(Offset);Camera->SetRelativeRotation((-Offset).Rotation());
    if(Earth)Earth->Update(F);
    if(Exhaust)Exhaust->Update(F,Camera->GetComponentLocation());
}
void AOrbiterPawn::Tick(float DT) {
    Super::Tick(DT);if(!Sim||!Error.IsEmpty())return;auto *PC=Cast<APlayerController>(GetController());if(!PC)return;
    try {
        auto &F=Sim->Flight;
        native::Input Input;
        if(RcsDemo)Input.yaw=.35;
        if(!SmokeFrames) {
        if(PC->WasInputKeyJustPressed(EKeys::M))F.glider.rcsMode=(F.glider.rcsMode+1)%3;
        if(PC->WasInputKeyJustPressed(EKeys::K))F.assist=F.assist==native::Assist::KillRotation?native::Assist::Free:native::Assist::KillRotation;
        if(PC->WasInputKeyJustPressed(EKeys::T))F.warp=FMath::Min(10000.,F.warp*10);
        if(PC->WasInputKeyJustPressed(EKeys::Y))F.warp=FMath::Max(1.,F.warp/10);
        if(PC->WasInputKeyJustPressed(EKeys::F5))F.glider.hoverControl.attitudeMode=F.glider.hoverControl.attitudeMode?0:1;
        if(PC->WasInputKeyJustPressed(EKeys::W)&&Earth)Earth->SetWeather((Earth->Weather()+1)%4);
        if(PC->WasInputKeyJustPressed(EKeys::SpaceBar))F.paused=!F.paused;
        if(PC->WasInputKeyJustPressed(EKeys::R))LoadFlight(FParse::Param(FCommandLine::Get(),TEXT("surface")));
        if(PC->WasInputKeyJustPressed(EKeys::X))F.cutEngines();
        if(PC->WasInputKeyJustPressed(EKeys::G))F.glider.toggle(native::Part::Gear);
        if(PC->WasInputKeyJustPressed(EKeys::C))F.glider.toggle(native::Part::Nose);
        if(PC->WasInputKeyJustPressed(EKeys::F))F.glider.toggle(native::Part::Radiator);
        if(PC->WasInputKeyJustPressed(EKeys::F6)){if(F.glider.hoverControl.holdActive&&F.glider.hoverControl.holdMode==1)F.setHoverThrottle(F.glider.hover);else F.setHoverHold(1,F.altitude());}
        if(PC->WasInputKeyJustPressed(EKeys::F7)){if(F.glider.hoverControl.holdActive&&F.glider.hoverControl.holdMode==2)F.setHoverThrottle(F.glider.hover);else F.setHoverHold(2,0);}
        if(PC->IsInputKeyDown(EKeys::Equals))F.throttle=FMath::Min(1.,F.throttle+DT*.4);
        if(PC->IsInputKeyDown(EKeys::Hyphen))F.throttle=FMath::Max(0.,F.throttle-DT*.4);
        if(PC->IsInputKeyDown(EKeys::RightBracket))F.setHoverThrottle(F.glider.hover+DT*.35);
        if(PC->IsInputKeyDown(EKeys::LeftBracket))F.setHoverThrottle(F.glider.hover-DT*.35);
        Input.pitch=PC->IsInputKeyDown(EKeys::Down)-PC->IsInputKeyDown(EKeys::Up);Input.yaw=PC->IsInputKeyDown(EKeys::Right)-PC->IsInputKeyDown(EKeys::Left);Input.roll=PC->IsInputKeyDown(EKeys::Q)-PC->IsInputKeyDown(EKeys::E);
        Input.translate=PC->IsInputKeyDown(EKeys::NumPadEight)-PC->IsInputKeyDown(EKeys::NumPadTwo);
        Input.lateral=PC->IsInputKeyDown(EKeys::NumPadSix)-PC->IsInputKeyDown(EKeys::NumPadFour);
        Input.vertical=PC->IsInputKeyDown(EKeys::NumPadNine)-PC->IsInputKeyDown(EKeys::NumPadThree);
        Input.leftBrake=PC->IsInputKeyDown(EKeys::Comma);Input.rightBrake=PC->IsInputKeyDown(EKeys::Period);
        }
        F.advance(DT,Input);
        if(PC->IsInputKeyDown(EKeys::LeftMouseButton)){float X,Y;PC->GetInputMouseDelta(X,Y);CameraYaw+=X*.2;CameraPitch=FMath::Clamp(CameraPitch-Y*.2f,-75.f,75.f);}
        if(PC->WasInputKeyJustPressed(EKeys::MouseScrollUp))CameraDistance=FMath::Max(1400.f,CameraDistance*.9f);
        if(PC->WasInputKeyJustPressed(EKeys::MouseScrollDown))CameraDistance=FMath::Min(100000.f,CameraDistance*1.1f);
        UpdateVisuals();
        if(SmokeFrames>0) {
            ++Frames;
            if(Frames==120)SampleStart=FPlatformTime::Seconds();
            if(Frames==SmokeFrames&&!CapturePath.IsEmpty())FScreenshotRequest::RequestScreenshot(CapturePath,false,false);
            if(Frames==SmokeFrames+10) {
                double Lat,Lon;native::earthCoordinates(F.position,F.mjd,F.elapsed,Lat,Lon);
                UE_LOG(LogTemp,Display,TEXT("ORBITER_SMOKE_OK altitude=%.3f speed=%.3f lat=%.3f lon=%.3f particles=%d fps=%.1f gpu_ms=%.2f"),F.altitude(),F.velocity.length(),Lat*DEG,Lon*DEG,Exhaust?Exhaust->ParticleCount():0,(Frames-120)/(FPlatformTime::Seconds()-SampleStart),FPlatformTime::ToMilliseconds(RHIGetGPUFrameCycles()));
                FPlatformMisc::RequestExit(false);
            }
        }
    }catch(const std::exception &E){Error=UTF8_TO_TCHAR(E.what());}
}
FString AOrbiterPawn::Readout() const {
    if(!Error.IsEmpty())return TEXT("Orbiter could not load: ")+Error;if(!Sim)return TEXT("Loading Orbiter...");auto &F=Sim->Flight;
    return FString::Printf(TEXT("Orbiter · Unreal Engine 5.8 · native arm64\nWeather %s (W) · visual preset\nDelta-glider  |  Alt %.1f km  |  Speed %.1f m/s\nMain %.0f%%  Hover %.0f%%  Fuel %.0f kg  |  %s\nRCS %s (M) · %.1f kg · K kill rotation · T/Y time %.0fx\n\n+/- main thrust   [/] hover   X cutoff   Arrows/Q/E attitude\nG gear   C nose   F radiator   F6/F7 hover hold   Space pause\nDrag to orbit camera · Scroll to zoom · R restart"),Earth?*Earth->WeatherName():TEXT("Loading"),F.altitude()/1000,F.velocity.length(),F.throttle*100,F.glider.hover*100,F.fuel,F.paused?TEXT("PAUSED"):TEXT("FLIGHT"),F.glider.rcsMode==0?TEXT("OFF"):F.glider.rcsMode==1?TEXT("ROTATION"):TEXT("TRANSLATION"),F.rcs,F.warp);
}
void AOrbiterHUD::DrawHUD() {Super::DrawHUD();if(auto *P=Cast<AOrbiterPawn>(GetOwningPawn()))DrawText(P->Readout(),FLinearColor(.75,1,.8),24,24,GEngine->GetSmallFont(),1.3f,false);}
AOrbiterGameMode::AOrbiterGameMode(){DefaultPawnClass=AOrbiterPawn::StaticClass();HUDClass=AOrbiterHUD::StaticClass();}
