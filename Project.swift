import ProjectDescription

let project = Project(
    name: "AIImageEditor",
    targets: [
        .target(
            name: "AIImageEditorCore",
            destinations: .macOS,
            product: .staticFramework,
            bundleId: "io.tuist.AIImageEditorCore",
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
            bundleId: "io.tuist.AIImageEditor",
            deploymentTargets: .macOS("13.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDocumentTypes": [
                    [
                        "CFBundleTypeName": "AI Image Editor Project",
                        "CFBundleTypeRole": "Editor",
                        "LSItemContentTypes": ["io.tuist.AIImageEditor.aiproj"],
                        "LSHandlerRank": "Owner",
                    ],
                ],
                "UTExportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "io.tuist.AIImageEditor.aiproj",
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
            bundleId: "io.tuist.aiimageeditor.cli",
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
            bundleId: "io.tuist.aiimageeditor.mcp",
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
            bundleId: "io.tuist.AIImageEditorTests",
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
