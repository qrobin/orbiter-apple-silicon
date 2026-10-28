#include "OrbiterCore.h"
#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "Misc/Paths.h"
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
#endif
