#!/usr/bin/env python3
"""Deterministic project generator; Python standard library only. Checked-in pbxproj is authoritative."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, value): objects[ident(name)] = value; return ident(name)
def arr(ids): return '(' + ', '.join(ids) + ',)'
sources = sorted(root.glob('Dreadline/**/*.swift'))
tests = sorted(root.glob('DreadlineTests/*.swift'))
app_builds=[]; test_builds=[]; files=[]
for path in sources + tests:
    rel = str(path.relative_to(root)); f = add(rel, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "'+rel+'"; sourceTree = "<group>";}'); files.append(f)
    if path in sources:
        app_builds.append(add('app-'+rel, '{isa = PBXBuildFile; fileRef = '+f+';}'))
    if path in tests or (path in sources and path.name != 'DreadlineApp.swift'):
        test_builds.append(add('test-'+rel, '{isa = PBXBuildFile; fileRef = '+f+';}'))
app_product=add('app-product','{isa = PBXFileReference; explicitFileType = wrapper.application; path = Dreadline.app; sourceTree = BUILT_PRODUCTS_DIR;}')
test_product=add('test-product','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = DreadlineTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
products=add('products','{isa = PBXGroup; name = Products; children = '+arr([app_product,test_product])+'; sourceTree = "<group>";}')
group=add('main-group','{isa = PBXGroup; children = '+arr(files+[products])+'; sourceTree = "<group>";}')
common='MACOSX_DEPLOYMENT_TARGET = 14.0; SDKROOT = macosx; SWIFT_VERSION = 6.0; SWIFT_STRICT_CONCURRENCY = complete; CLANG_ENABLE_MODULES = YES; GCC_C_LANGUAGE_STANDARD = gnu17; CLANG_ENABLE_OBJC_ARC = YES; '
def configs(name, extra):
    ids=[]
    for mode in ['Debug','Release']:
        settings=common+extra+' SWIFT_OPTIMIZATION_LEVEL = '+('"-Onone"' if mode=='Debug' else '"-O"')+'; '
        if mode=='Debug': settings+='ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf; '
        else: settings+='DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; '
        ids.append(add(name+mode,'{isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {'+settings+'};}'))
    return add(name+'configs','{isa = XCConfigurationList; buildConfigurations = '+arr(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
proj_configs=configs('project','')
app_configs=configs('app','PRODUCT_NAME = Dreadline; PRODUCT_BUNDLE_IDENTIFIER = xyz.dreadline.app; INFOPLIST_FILE = Dreadline/Info.plist; CODE_SIGN_ENTITLEMENTS = Dreadline/Dreadline.entitlements; CODE_SIGN_STYLE = Automatic; ENABLE_APP_SANDBOX = YES; ENABLE_HARDENED_RUNTIME = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; OTHER_LDFLAGS = "-lsqlite3";')
test_configs=configs('test','PRODUCT_NAME = DreadlineTests; PRODUCT_BUNDLE_IDENTIFIER = xyz.dreadline.tests; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; OTHER_LDFLAGS = "-lsqlite3";')
app_sources=add('app-sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+arr(app_builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
test_sources=add('test-sources','{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = '+arr(test_builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
app_target=add('app-target','{isa = PBXNativeTarget; name = Dreadline; productName = Dreadline; productType = "com.apple.product-type.application"; productReference = '+app_product+'; buildConfigurationList = '+app_configs+'; buildPhases = '+arr([app_sources])+'; buildRules = (); dependencies = ();}')
test_target=add('test-target','{isa = PBXNativeTarget; name = DreadlineTests; productName = DreadlineTests; productType = "com.apple.product-type.bundle.unit-test"; productReference = '+test_product+'; buildConfigurationList = '+test_configs+'; buildPhases = '+arr([test_sources])+'; buildRules = (); dependencies = ();}')
project=add('project','{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2710;}; buildConfigurationList = '+proj_configs+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = '+group+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+arr([app_target,test_target])+';}')
(root/'Dreadline.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+';}\n')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2710" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Dreadline.app" BlueprintName="Dreadline" ReferencedContainer="container:Dreadline.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{test_target}" BuildableName="DreadlineTests.xctest" BlueprintName="DreadlineTests" ReferencedContainer="container:Dreadline.xcodeproj"/></TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="Dreadline.app" BlueprintName="Dreadline" ReferencedContainer="container:Dreadline.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(root/'Dreadline.xcodeproj/xcshareddata/xcschemes/Dreadline.xcscheme').write_text(scheme)
