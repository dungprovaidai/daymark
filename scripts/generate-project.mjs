// Reproducible Xcode project generation. Node.js is needed only to regenerate.
// The generated .xcodeproj is checked in and opens directly in Xcode.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const id = name => crypto.createHash('sha1').update(name).digest('hex').slice(0, 24).toUpperCase();
const objects = {};
const add = (name, value) => (objects[id(name)] = value, id(name));
const walk = directory => fs.readdirSync(directory, { withFileTypes: true }).flatMap(item => item.isDirectory() ? walk(path.join(directory, item.name)) : [path.join(directory, item.name)]);
const sourceFiles = walk(path.join(root, 'Daymark')).filter(x => x.endsWith('.swift')).map(x => path.relative(path.join(root, 'Daymark'), x).replaceAll('\\', '/')).sort();
const tests = walk(path.join(root, 'DaymarkTests')).filter(x => x.endsWith('.swift')).map(x => path.basename(x)).sort();
const sharedFiles = walk(path.join(root, 'Shared')).filter(x => x.endsWith('.swift')).map(x => path.relative(root, x).replaceAll('\\', '/')).sort();
const widgetFiles = walk(path.join(root, 'DaymarkWidgets')).filter(x => x.endsWith('.swift')).map(x => path.relative(root, x).replaceAll('\\', '/')).sort();
const refs = sourceFiles.map(file => add('source:' + file, { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: file, sourceTree: '<group>' }));
const sourceBuilds = sourceFiles.map(file => add('build:' + file, { isa: 'PBXBuildFile', fileRef: id('source:' + file) }));
const testRefs = tests.map(file => add('test:' + file, { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: file, sourceTree: '<group>' }));
const testBuilds = tests.map(file => add('test-build:' + file, { isa: 'PBXBuildFile', fileRef: id('test:' + file) }));
const sharedRefs = sharedFiles.map(file => add('shared:' + file, { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: file, sourceTree: '<group>' }));
const sharedAppBuilds = sharedFiles.map(file => add('shared-app-build:' + file, { isa: 'PBXBuildFile', fileRef: id('shared:' + file) }));
const sharedWidgetBuilds = sharedFiles.map(file => add('shared-widget-build:' + file, { isa: 'PBXBuildFile', fileRef: id('shared:' + file) }));
const widgetRefs = widgetFiles.map(file => add('widget:' + file, { isa: 'PBXFileReference', lastKnownFileType: 'sourcecode.swift', path: path.basename(file), sourceTree: '<group>' }));
const widgetBuilds = widgetFiles.map(file => add('widget-build:' + file, { isa: 'PBXBuildFile', fileRef: id('widget:' + file) }));
const assets = add('assets', { isa: 'PBXFileReference', lastKnownFileType: 'folder.assetcatalog', path: 'Assets.xcassets', sourceTree: '<group>' });
const privacy = add('privacy', { isa: 'PBXFileReference', lastKnownFileType: 'text.xml', path: 'PrivacyInfo.xcprivacy', sourceTree: '<group>' });
const appInfo = add('app-info', { isa: 'PBXFileReference', lastKnownFileType: 'text.plist.xml', path: 'Info.plist', sourceTree: '<group>' });
const appEntitlements = add('app-entitlements', { isa: 'PBXFileReference', lastKnownFileType: 'text.plist.entitlements', path: 'Daymark.entitlements', sourceTree: '<group>' });
const widgetInfo = add('widget-info', { isa: 'PBXFileReference', lastKnownFileType: 'text.plist.xml', path: 'Info.plist', sourceTree: '<group>' });
const widgetEntitlements = add('widget-entitlements', { isa: 'PBXFileReference', lastKnownFileType: 'text.plist.entitlements', path: 'DaymarkWidgets.entitlements', sourceTree: '<group>' });
const assetsBuild = add('assets-build', { isa: 'PBXBuildFile', fileRef: assets });
const privacyBuild = add('privacy-build', { isa: 'PBXBuildFile', fileRef: privacy });
const appProduct = add('app-product', { isa: 'PBXFileReference', explicitFileType: 'wrapper.application', includeInIndex: 0, path: 'Daymark.app', sourceTree: 'BUILT_PRODUCTS_DIR' });
const widgetProduct = add('widget-product', { isa: 'PBXFileReference', explicitFileType: 'wrapper.app-extension', includeInIndex: 0, path: 'DaymarkWidgets.appex', sourceTree: 'BUILT_PRODUCTS_DIR' });
const testProduct = add('test-product', { isa: 'PBXFileReference', explicitFileType: 'wrapper.cfbundle', includeInIndex: 0, path: 'DaymarkTests.xctest', sourceTree: 'BUILT_PRODUCTS_DIR' });
const appGroup = add('app-group', { isa: 'PBXGroup', children: [...refs, assets, privacy, appInfo, appEntitlements], path: 'Daymark', sourceTree: '<group>' });
const sharedGroup = add('shared-group', { isa: 'PBXGroup', children: sharedRefs, name: 'Shared', sourceTree: '<group>' });
const widgetGroup = add('widget-group', { isa: 'PBXGroup', children: [...widgetRefs, widgetInfo, widgetEntitlements], path: 'DaymarkWidgets', sourceTree: '<group>' });
const testGroup = add('test-group', { isa: 'PBXGroup', children: testRefs, path: 'DaymarkTests', sourceTree: '<group>' });
const products = add('products', { isa: 'PBXGroup', children: [appProduct, widgetProduct, testProduct], name: 'Products', sourceTree: '<group>' });
const main = add('main', { isa: 'PBXGroup', children: [appGroup, sharedGroup, widgetGroup, testGroup, products], sourceTree: '<group>' });
const sourcePhase = add('sources', { isa: 'PBXSourcesBuildPhase', buildActionMask: 2147483647, files: [...sourceBuilds, ...sharedAppBuilds], runOnlyForDeploymentPostprocessing: 0 });
const resourcePhase = add('resources', { isa: 'PBXResourcesBuildPhase', buildActionMask: 2147483647, files: [assetsBuild, privacyBuild], runOnlyForDeploymentPostprocessing: 0 });
const frameworkPhase = add('frameworks', { isa: 'PBXFrameworksBuildPhase', buildActionMask: 2147483647, files: [], runOnlyForDeploymentPostprocessing: 0 });
const testPhase = add('test-sources', { isa: 'PBXSourcesBuildPhase', buildActionMask: 2147483647, files: testBuilds, runOnlyForDeploymentPostprocessing: 0 });
const testFrameworks = add('test-frameworks', { isa: 'PBXFrameworksBuildPhase', buildActionMask: 2147483647, files: [], runOnlyForDeploymentPostprocessing: 0 });
const widgetSourcePhase = add('widget-sources', { isa: 'PBXSourcesBuildPhase', buildActionMask: 2147483647, files: [...widgetBuilds, ...sharedWidgetBuilds], runOnlyForDeploymentPostprocessing: 0 });
const widgetResourcePhase = add('widget-resources', { isa: 'PBXResourcesBuildPhase', buildActionMask: 2147483647, files: [], runOnlyForDeploymentPostprocessing: 0 });
const widgetFrameworkPhase = add('widget-frameworks', { isa: 'PBXFrameworksBuildPhase', buildActionMask: 2147483647, files: [], runOnlyForDeploymentPostprocessing: 0 });
const widgetEmbedBuild = add('widget-embed-build', { isa: 'PBXBuildFile', fileRef: widgetProduct, settings: { ATTRIBUTES: ['RemoveHeadersOnCopy'] } });
const embedPhase = add('embed-extensions', { isa: 'PBXCopyFilesBuildPhase', buildActionMask: 2147483647, dstPath: '', dstSubfolderSpec: 13, files: [widgetEmbedBuild], name: 'Embed Foundation Extensions', runOnlyForDeploymentPostprocessing: 0 });
const projectSettings = {
  CLANG_ENABLE_MODULES: 'YES', CLANG_ENABLE_OBJC_ARC: 'YES', SDKROOT: 'iphoneos', IPHONEOS_DEPLOYMENT_TARGET: '17.0', SWIFT_VERSION: '5.0',
  ENABLE_USER_SCRIPT_SANDBOXING: 'YES', GCC_C_LANGUAGE_STANDARD: 'gnu17', CLANG_CXX_LANGUAGE_STANDARD: 'gnu++20',
  SWIFT_STRICT_CONCURRENCY: 'targeted',
};
const appSettings = {
  PRODUCT_NAME: '$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER: 'com.example.Daymark', CODE_SIGN_STYLE: 'Automatic',
  GENERATE_INFOPLIST_FILE: 'NO', INFOPLIST_FILE: 'Daymark/Info.plist',
  CODE_SIGN_ENTITLEMENTS: 'Daymark/Daymark.entitlements',
  TARGETED_DEVICE_FAMILY: '1,2', SUPPORTS_MACCATALYST: 'NO',
  ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: 'AccentColor',
  MARKETING_VERSION: '1.0.0', CURRENT_PROJECT_VERSION: '1',
  LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks'],
  SWIFT_EMIT_LOC_STRINGS: 'YES',
};
const widgetSettings = {
  PRODUCT_NAME: '$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER: 'com.example.Daymark.Widgets', CODE_SIGN_STYLE: 'Automatic',
  GENERATE_INFOPLIST_FILE: 'NO', INFOPLIST_FILE: 'DaymarkWidgets/Info.plist',
  CODE_SIGN_ENTITLEMENTS: 'DaymarkWidgets/DaymarkWidgets.entitlements',
  SKIP_INSTALL: 'YES', APPLICATION_EXTENSION_API_ONLY: 'YES',
  TARGETED_DEVICE_FAMILY: '1,2', SUPPORTS_MACCATALYST: 'NO',
  MARKETING_VERSION: '1.0.0', CURRENT_PROJECT_VERSION: '1',
  LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'],
  SWIFT_EMIT_LOC_STRINGS: 'YES',
};
const testSettings = {
  PRODUCT_NAME: '$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER: 'com.example.DaymarkTests', CODE_SIGN_STYLE: 'Automatic',
  GENERATE_INFOPLIST_FILE: 'YES', TARGETED_DEVICE_FAMILY: '1,2', BUNDLE_LOADER: '$(TEST_HOST)',
  TEST_HOST: '$(BUILT_PRODUCTS_DIR)/Daymark.app/Daymark',
  LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks'],
};
function configs(prefix, settings) {
  const debug = add(prefix + '-debug', { isa: 'XCBuildConfiguration', name: 'Debug', buildSettings: { ...settings, DEBUG_INFORMATION_FORMAT: 'dwarf', SWIFT_OPTIMIZATION_LEVEL: '-Onone', SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG $(inherited)', ENABLE_TESTABILITY: 'YES', ONLY_ACTIVE_ARCH: 'YES' } });
  const release = add(prefix + '-release', { isa: 'XCBuildConfiguration', name: 'Release', buildSettings: { ...settings, DEBUG_INFORMATION_FORMAT: 'dwarf-with-dsym', SWIFT_COMPILATION_MODE: 'wholemodule', SWIFT_OPTIMIZATION_LEVEL: '-O', VALIDATE_PRODUCT: 'YES' } });
  return add(prefix + '-configs', { isa: 'XCConfigurationList', buildConfigurations: [debug, release], defaultConfigurationIsVisible: 0, defaultConfigurationName: 'Release' });
}
const appConfig = configs('app', appSettings);
const widgetConfig = configs('widget', widgetSettings);
const testConfig = configs('test', testSettings);
const projectConfig = configs('project', projectSettings);
const widgetProxy = add('widget-proxy', { isa: 'PBXContainerItemProxy', containerPortal: id('project'), proxyType: 1, remoteGlobalIDString: id('widget-target'), remoteInfo: 'DaymarkWidgets' });
const widgetDependency = add('widget-dependency', { isa: 'PBXTargetDependency', target: id('widget-target'), targetProxy: widgetProxy });
const proxy = add('test-proxy', { isa: 'PBXContainerItemProxy', containerPortal: id('project'), proxyType: 1, remoteGlobalIDString: id('app-target'), remoteInfo: 'Daymark' });
const dependency = add('test-dependency', { isa: 'PBXTargetDependency', target: id('app-target'), targetProxy: proxy });
const appTarget = add('app-target', { isa: 'PBXNativeTarget', buildConfigurationList: appConfig, buildPhases: [sourcePhase, frameworkPhase, resourcePhase, embedPhase], buildRules: [], dependencies: [widgetDependency], name: 'Daymark', productName: 'Daymark', productReference: appProduct, productType: 'com.apple.product-type.application' });
const widgetTarget = add('widget-target', { isa: 'PBXNativeTarget', buildConfigurationList: widgetConfig, buildPhases: [widgetSourcePhase, widgetFrameworkPhase, widgetResourcePhase], buildRules: [], dependencies: [], name: 'DaymarkWidgets', productName: 'DaymarkWidgets', productReference: widgetProduct, productType: 'com.apple.product-type.app-extension' });
const testTarget = add('test-target', { isa: 'PBXNativeTarget', buildConfigurationList: testConfig, buildPhases: [testPhase, testFrameworks], buildRules: [], dependencies: [dependency], name: 'DaymarkTests', productName: 'DaymarkTests', productReference: testProduct, productType: 'com.apple.product-type.bundle.unit-test' });
const project = add('project', { isa: 'PBXProject', attributes: { BuildIndependentTargetsInParallel: 'YES', LastUpgradeCheck: '1600', TargetAttributes: { [appTarget]: { CreatedOnToolsVersion: '16.0' }, [widgetTarget]: { CreatedOnToolsVersion: '16.0', ProvisioningStyle: 'Automatic' }, [testTarget]: { CreatedOnToolsVersion: '16.0', TestTargetID: appTarget } } }, buildConfigurationList: projectConfig, compatibilityVersion: 'Xcode 14.0', developmentRegion: 'en', hasScannedForEncodings: 0, knownRegions: ['en', 'Base'], mainGroup: main, productRefGroup: products, projectDirPath: '', projectRoot: '', targets: [appTarget, widgetTarget, testTarget] });
function plist(value, depth = 0) {
  const tab = '\t'.repeat(depth);
  if (Array.isArray(value)) return `(\n${value.map(x => tab + '\t' + plist(x, depth + 1) + ',').join('\n')}\n${tab})`;
  if (value && typeof value === 'object') return `{\n${Object.entries(value).map(([key, val]) => `${tab}\t${JSON.stringify(key)} = ${plist(val, depth + 1)};`).join('\n')}\n${tab}}`;
  return typeof value === 'number' ? String(value) : JSON.stringify(value);
}
fs.writeFileSync(path.join(root, 'Daymark.xcodeproj/project.pbxproj'), '// !$*UTF8*$!\n' + plist({ archiveVersion: 1, classes: {}, objectVersion: 56, objects, rootObject: project }) + '\n');
const reference = (target, product, name) => `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${target}" BuildableName="${product}" BlueprintName="${name}" ReferencedContainer="container:Daymark.xcodeproj"/>`;
const appRef = reference(appTarget, 'Daymark.app', 'Daymark');
const testRef = reference(testTarget, 'DaymarkTests.xctest', 'DaymarkTests');
fs.writeFileSync(path.join(root, 'Daymark.xcodeproj/xcshareddata/xcschemes/Daymark.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
  <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${appRef}</BuildActionEntry>
  <BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">${testRef}</BuildActionEntry>
 </BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">${testRef}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${appRef}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">${appRef}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/>
 <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
`);
console.log(`Generated Daymark.xcodeproj: ${sourceFiles.length} app sources, ${tests.length} test sources, ${Object.keys(objects).length} project objects.`);
