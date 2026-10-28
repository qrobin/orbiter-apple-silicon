using UnrealBuildTool;
using System.IO;
public class OrbiterUE : ModuleRules {
    public OrbiterUE(ReadOnlyTargetRules Target) : base(Target) {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        bUseUnity = false;
        bEnableExceptions = true;
        PublicDependencyModuleNames.AddRange(new string[] {"Core", "CoreUObject", "Engine", "InputCore", "ProceduralMeshComponent", "RenderCore", "RHI", "ImageWrapper", "Niagara"});
        string Root = Path.GetFullPath(Path.Combine(ModuleDirectory, "../../.."));
        PrivateIncludePaths.Add(Path.Combine(Root, "Native"));
        PrivateIncludePaths.Add(Path.Combine(Root, "Src/Orbiter"));
        PrivateDefinitions.Add("ORBITER_NATIVE=1");
        PublicAdditionalLibraries.Add(Path.Combine(Root, "build/unreal-arm64/Native/libOrbiterFlightCore.a"));
    }
}
