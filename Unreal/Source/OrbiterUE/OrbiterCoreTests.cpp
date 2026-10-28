#include "OrbiterCore.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
#include "OrbiterFrame.h"
THIRD_PARTY_INCLUDES_START
#include "Exhaust.h"
THIRD_PARTY_INCLUDES_END
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOrbiterCoreBridgeTest,"Orbiter.NativeBridge.FlightAndHover",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FOrbiterCoreBridgeTest::RunTest(const FString &) {
    const FString Data=FPaths::ProjectContentDir()/TEXT("OrbiterData");
    try {
        native::Flight Flight;
        Flight.load(TCHAR_TO_UTF8(*(Data/TEXT("Scenarios/DG Mk4 in orbit.scn"))));
        TestTrue(TEXT("Original orbit loaded"),Flight.altitude()>100000);
        for(int I=0;I<120;++I)Flight.advance(1./120);
        TestTrue(TEXT("Original orbital integrator advances"),Flight.elapsed>.99);
        const auto Mesh=native::loadMesh(TCHAR_TO_UTF8(*(Data/TEXT("Meshes/deltaglider_ns.msh"))));
        TestTrue(TEXT("Original Delta-glider geometry loaded"),Mesh.groups.size()>50);
        Flight.load(TCHAR_TO_UTF8(*(Data/TEXT("Scenarios/Cape Canaveral native.scn"))));
        TestTrue(TEXT("Altitude hold accepted"),Flight.setHoverHold(1,100));
        for(int I=0;I<7200;++I)Flight.advance(1./120);
        TestTrue(TEXT("Shared hover controller holds 100 m"),FMath::Abs(Flight.altitude()-100)<.5);
        Flight.cutEngines();
        TestFalse(TEXT("Cutoff cancels hold"),Flight.glider.hoverControl.holdActive);
    }catch(const std::exception &E){AddError(UTF8_TO_TCHAR(E.what()));}
    return !HasAnyErrors();
}
IMPLEMENT_SIMPLE_AUTOMATION_TEST(FOrbiterExhaustFrameTest,"Orbiter.NativeBridge.NozzleFrame",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FOrbiterExhaustFrameTest::RunTest(const FString &) {
    native::Flight Flight;Flight.glider.mainLevel=.8;
    for(const Vector &Forward:{Vector(1,2,3),Vector(-3,1,.5),Vector(0,-1,1)}) {
        Flight.align(Forward);
        const FVector SpawnOffset(150,-75,100);
        const FTransform RenderFrame(OrbiterFrame::Rotation(Flight),SpawnOffset);
        for(const auto &Nozzle:native::gliderExhaust(Flight)) {
            const auto &P=Nozzle.position;
            const FVector Expected=OrbiterFrame::Point(Flight.right*P.x+Flight.up*P.y+Flight.forward*P.z)*100+SpawnOffset;
            const FVector Actual=RenderFrame.TransformPosition(OrbiterFrame::Point(P)*100);
            TestTrue(TEXT("Nozzle mouths follow the visible ship, including map spawn offsets"),Actual.Equals(Expected,1e-5));
            const auto &D=Nozzle.direction;
            const FVector ExpectedDirection=OrbiterFrame::Point(Flight.right*D.x+Flight.up*D.y+Flight.forward*D.z);
            TestTrue(TEXT("Jet axes follow the visible ship attitude"),RenderFrame.TransformVectorNoScale(OrbiterFrame::Point(D)).Equals(ExpectedDirection,1e-6));
        }
    }
    return !HasAnyErrors();
}
#endif
