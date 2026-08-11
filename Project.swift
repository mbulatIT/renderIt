import ProjectDescription

let project = Project(
    name: "AIImageEditor",
    targets: [
        .target(
            name: "AIImageEditorCore",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "com.bulat.aiimageeditor.core",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: ["AIImageEditorCore/Sources/**"],
            resources: ["AIImageEditorCore/Resources/**"],
            dependencies: []
        ),
        .target(
            name: "AIImageEditor",
            destinations: .macOS,
            product: .app,
            bundleId: "com.bulat.aiimageeditor",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .extendingDefault(with: [
                "LSApplicationCategoryType": "public.app-category.graphics-design",
                "CFBundleDocumentTypes": [
                    [
                        "CFBundleTypeName": "AI Image Editor Project",
                        "CFBundleTypeRole": "Editor",
                        "LSItemContentTypes": ["com.bulat.aiimageeditor.aiproj"],
                        "LSHandlerRank": "Owner",
                    ],
                ],
                "UTExportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.bulat.aiimageeditor.aiproj",
                        "UTTypeDescription": "AI Image Editor Project",
                        "UTTypeConformsTo": ["public.json"],
                        "UTTypeTagSpecification": [
                            "public.filename-extension": ["aiproj"],
                        ],
                    ],
                ],
            ]),
            sources: ["AIImageEditor/Sources/**"],
            resources: ["AIImageEditor/Resources/**"],
            dependencies: [
                .target(name: "AIImageEditorCore"),
            ]
        ),
        .target(
            name: "aiimageeditor-cli",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.bulat.aiimageeditor.cli",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: ["CLI/Sources/**"],
            dependencies: [
                .target(name: "AIImageEditorCore"),
            ]
        ),
        .target(
            name: "aiimageeditor-mcp",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.bulat.aiimageeditor.mcp",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: ["MCP/Sources/**"],
            dependencies: [
                .target(name: "AIImageEditorCore"),
            ]
        ),
        .target(
            name: "AIImageEditorTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.bulat.aiimageeditor.tests",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .default,
            sources: ["AIImageEditor/Tests/**"],
            resources: [],
            dependencies: [
                .target(name: "AIImageEditor"),
                .target(name: "AIImageEditorCore"),
            ]
        ),
    ]
)
