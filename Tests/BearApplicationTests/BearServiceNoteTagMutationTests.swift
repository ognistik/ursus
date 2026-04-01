import BearApplication
import BearCore
import Foundation
import Logging
import Testing

@Test
func addTagsUsesTemplateTagSlotAndSkipsImplicitParentTag() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox #parent/subtag\n---\nLine 1",
        tags: ["0-inbox", "parent", "parent/subtag"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.addTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["parent", "client work"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox #parent/subtag #client work#\n---\nLine 1")
    #expect(receipt.addedTags == ["client work"])
    #expect(receipt.removedTags.isEmpty)
    #expect(receipt.skippedTags == ["parent"])
}

@Test
func addTagsPrefersMatchedTemplateTagSlotOverRawTagClusterInContent() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: """
        ---
        #0-inbox
        ---
        #content-cluster
        Body line.
        """,
        tags: ["0-inbox", "content-cluster"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.addTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["new-tag"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Inbox

    ---
    #0-inbox #new-tag
    ---
    #content-cluster
    Body line.
    """)
    #expect(receipt.addedTags == ["new-tag"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func removeTagsUsesTemplateTagSlotAndDoesNotTreatImplicitParentAsLiteral() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "---\n#0-inbox #parent/subtag\n---\nLine 1",
        tags: ["0-inbox", "parent", "parent/subtag"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.removeTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["parent", "parent/subtag"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\n---\n#0-inbox\n---\nLine 1")
    #expect(receipt.addedTags.isEmpty)
    #expect(receipt.removedTags == ["parent/subtag"])
    #expect(receipt.skippedTags == ["parent"])
}

@Test
func removeTagsFromTemplateMatchedNoteAlsoRemovesLiteralTagsInsideContent() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: """
        ---
        #0-inbox #project-x
        ---
        Body has #project-x and #keep-tag.
        """,
        tags: ["0-inbox", "project-x", "keep-tag"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.removeTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["project-x"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Inbox

    ---
    #0-inbox
    ---
    Body has and #keep-tag.
    """)
    #expect(receipt.removedTags == ["project-x"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func removeTagsFromRawBodyRemovesLiteralTokensAndCleansWhitespace() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Testing #old-tag and #keep-tag in body",
        tags: ["old-tag", "keep-tag"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await service.removeTags([
        NoteTagsRequest(
            noteID: "note-1",
            tags: ["old-tag"],
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\nTesting and #keep-tag in body")
    #expect(receipt.removedTags == ["old-tag"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func addTagsUsesFirstRawTagClusterWhenNoteDoesNotMatchTemplate() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: """
        Intro

        #project-x
        Details
        """,
        tags: ["project-x"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.addTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["deep work"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Inbox

    Intro

    #project-x #deep work#
    Details
    """)
    #expect(receipt.addedTags == ["deep work"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func addTagsAppliesTemplateWhenEnabledAndNoTagClusterExists() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.addTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["deep work", "project-x"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Inbox

    ---
    #deep work# #project-x
    ---
    Line 1
    """)
    #expect(receipt.addedTags == ["deep work", "project-x"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func addTagsFailsClearlyWhenTemplateIsMissingAndRequired() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    do {
        try await withTemporaryNoteTemplate(nil) {
            _ = try await service.addTags([
                NoteTagsRequest(
                    noteID: "note-1",
                    tags: ["deep work"],
                    presentation: BearPresentationOptions(),
                    expectedVersion: 3
                ),
            ])
        }
        Issue.record("Expected addTags to fail when template management requires a missing template.")
    } catch let error as BearError {
        #expect(error.errorDescription?.contains("template.md is missing") == true)
    }

    #expect(await transport.replaceCalls.isEmpty)
}

@Test
func addTagsFailsClearlyWhenTemplateLacksTagsSlotAndRequired() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    do {
        try await withTemporaryNoteTemplate("{{content}}\n") {
            _ = try await service.addTags([
                NoteTagsRequest(
                    noteID: "note-1",
                    tags: ["deep work"],
                    presentation: BearPresentationOptions(),
                    expectedVersion: 3
                ),
            ])
        }
        Issue.record("Expected addTags to fail when template management requires a `{{tags}}` slot.")
    } catch let error as BearError {
        #expect(error.errorDescription?.contains("valid `{{tags}}` slot") == true)
    }

    #expect(await transport.replaceCalls.isEmpty)
}

@Test
func addTagsInsertsCanonicalTagLineAtTopWhenTemplateManagementIsDisabled() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false, defaultInsertPosition: .top),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await service.addTags([
        NoteTagsRequest(
            noteID: "note-1",
            tags: ["deep work", "project-x"],
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\n#deep work# #project-x\nLine 1")
    #expect(receipt.addedTags == ["deep work", "project-x"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func addTagsInsertsCanonicalTagLineAtBottomWhenTemplateManagementIsDisabled() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false, defaultInsertPosition: .bottom),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await service.addTags([
        NoteTagsRequest(
            noteID: "note-1",
            tags: ["deep work", "project-x"],
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == "# Inbox\n\nLine 1\n#deep work# #project-x")
    #expect(receipt.addedTags == ["deep work", "project-x"])
    #expect(receipt.skippedTags.isEmpty)
}

@Test
func removeTagsHandlesLiveStyleNonTemplateBodyFromBearDB() async throws {
    let rawText = """
    # No Template

    This note doesn’t follow the template

    #0-inbox #another tag# #codex-live/raw-added #codex live raw spaced#
    ---
    """
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "No Template",
        body: """
        This note doesn’t follow the template

        #0-inbox #another tag# #codex-live/raw-added #codex live raw spaced#
        ---
        """,
        rawText: rawText,
        tags: ["0-inbox", "another tag", "codex-live/raw-added", "codex live raw spaced", "codex-live"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await service.removeTags([
        NoteTagsRequest(
            noteID: "note-1",
            tags: ["codex-live", "codex-live/raw-added"],
            presentation: BearPresentationOptions(),
            expectedVersion: 3
        ),
    ])

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # No Template

    This note doesn’t follow the template

    #0-inbox #another tag# #codex live raw spaced#
    ---
    """)
    #expect(receipt.removedTags == ["codex-live/raw-added"])
    #expect(receipt.skippedTags == ["codex-live"])
}

@Test
func removeTagsHandlesLiveStyleTemplateBodyFromBearDB() async throws {
    let rawText = """
    # Codex Live Template 2026-03-26 16-48

    ---
    #0-inbox #codex-live-parent/subtag #codex live spaced# #codex-live-renamed #codex-live-extra
    ---
    Template live test body.
    """
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Codex Live Template 2026-03-26 16-48",
        body: """
        ---
        #0-inbox #codex-live-parent/subtag #codex live spaced# #codex-live-renamed #codex-live-extra
        ---
        Template live test body.
        """,
        rawText: rawText,
        tags: ["0-inbox", "codex-live-parent/subtag", "codex-live-parent", "codex live spaced", "codex-live-renamed", "codex-live-extra"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.removeTags([
            NoteTagsRequest(
                noteID: "note-1",
                tags: ["codex-live-parent", "codex-live-parent/subtag"],
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Codex Live Template 2026-03-26 16-48

    ---
    #0-inbox #codex live spaced# #codex-live-renamed #codex-live-extra
    ---
    Template live test body.
    """)
    #expect(receipt.removedTags == ["codex-live-parent/subtag"])
    #expect(receipt.skippedTags == ["codex-live-parent"])
}

@Test
func applyTemplateMigratesAllTagOnlyClustersPreservesInlineTagsAndCleansWhitespace() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: """
        Intro #inline-tag stays.

        #project-x
        #deep work#

        Middle paragraph.

        #project-x
        #review

        End with #keep-inline.
        """,
        tags: ["project-x", "deep work", "review", "inline-tag stays.", "keep-inline"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.applyTemplate([
            ApplyTemplateRequest(
                noteID: "note-1",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Inbox

    ---
    #project-x #deep work# #review
    ---
    Intro #inline-tag stays.

    Middle paragraph.

    End with #keep-inline.
    """)
    #expect(receipt.status == "applied")
    #expect(receipt.appliedTags == ["project-x", "deep work", "review"])
}

@Test
func applyTemplateMergesExistingTemplateTagsBeforeMigratedClusters() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: """
        ---
        #0-inbox #project-x
        ---
        Body line.

        #project-x
        #review
        """,
        tags: ["0-inbox", "project-x", "review"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.applyTemplate([
            ApplyTemplateRequest(
                noteID: "note-1",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Inbox

    ---
    #0-inbox #project-x #review
    ---
    Body line.
    """)
    #expect(receipt.appliedTags == ["0-inbox", "project-x", "review"])
}

@Test
func applyTemplateAppliesTemplateEvenWhenNoteHasNoTags() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.applyTemplate([
            ApplyTemplateRequest(
                noteID: "note-1",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    let receipt = try #require(receipts.first)
    #expect(replaceCall.fullText == """
    # Inbox

    ---

    ---
    Line 1
    """)
    #expect(receipt.appliedTags.isEmpty)
    #expect(receipt.status == "applied")
}

@Test
func applyTemplateReturnsUnchangedWhenNoteIsAlreadyNormalized() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: """
        ---
        #0-inbox #project-x
        ---
        Line 1
        """,
        tags: ["0-inbox", "project-x"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    let receipts = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.applyTemplate([
            ApplyTemplateRequest(
                noteID: "note-1",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let receipt = try #require(receipts.first)
    #expect(await transport.replaceCalls.isEmpty)
    #expect(receipt.status == "unchanged")
    #expect(receipt.appliedTags == ["0-inbox", "project-x"])
}

@Test
func applyTemplateUsesTemplateFileEvenWhenTemplateManagementIsDisabled() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Body line\n\n#project-x",
        tags: ["project-x"]
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    _ = try await withTemporaryNoteTemplate("---\n{{tags}}\n---\n{{content}}\n") {
        try await service.applyTemplate([
            ApplyTemplateRequest(
                noteID: "note-1",
                presentation: BearPresentationOptions(),
                expectedVersion: 3
            ),
        ])
    }

    let replaceCall = try #require(await transport.replaceCalls.first)
    #expect(replaceCall.fullText == """
    # Inbox

    ---
    #project-x
    ---
    Body line
    """)
}

@Test
func applyTemplateFailsClearlyWhenTemplateIsMissing() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    do {
        try await withTemporaryNoteTemplate(nil) {
            _ = try await service.applyTemplate([
                ApplyTemplateRequest(
                    noteID: "note-1",
                    presentation: BearPresentationOptions(),
                    expectedVersion: 3
                ),
            ])
        }
        Issue.record("Expected applyTemplate to fail when template.md is missing.")
    } catch let error as BearError {
        #expect(error.errorDescription?.contains("bear_apply_template") == true)
        #expect(error.errorDescription?.contains("template.md") == true)
    }

    #expect(await transport.replaceCalls.isEmpty)
}

@Test
func applyTemplateFailsClearlyWhenTemplateLacksTagsSlot() async throws {
    let note = makeNoteTagSourceNote(
        id: "note-1",
        title: "Inbox",
        body: "Line 1",
        tags: []
    )
    let transport = NoteTagRecordingWriteTransport()
    let service = BearService(
        configuration: makeNoteTagConfiguration(templateManagementEnabled: false),
        readStore: NoteTagReadStore(noteByID: ["note-1": note]),
        writeTransport: transport,
        logger: Logger(label: "BearServiceNoteTagMutationTests")
    )

    do {
        try await withTemporaryNoteTemplate("{{content}}\n") {
            _ = try await service.applyTemplate([
                ApplyTemplateRequest(
                    noteID: "note-1",
                    presentation: BearPresentationOptions(),
                    expectedVersion: 3
                ),
            ])
        }
        Issue.record("Expected applyTemplate to fail when template lacks a tags slot.")
    } catch let error as BearError {
        #expect(error.errorDescription?.contains("valid `{{content}}` and `{{tags}}` slots") == true)
    }

    #expect(await transport.replaceCalls.isEmpty)
}

private func makeNoteTagConfiguration(
    templateManagementEnabled: Bool = true,
    defaultInsertPosition: BearConfiguration.InsertDefault = .bottom
) -> BearConfiguration {
    BearConfiguration(
        databasePath: "/tmp/database.sqlite",
        inboxTags: ["0-inbox"],
        defaultInsertPosition: defaultInsertPosition,
        templateManagementEnabled: templateManagementEnabled,
        createOpensNoteByDefault: true,
        openUsesNewWindowByDefault: true,
        createAddsInboxTagsByDefault: true,
        tagsMergeMode: .append,
        defaultDiscoveryLimit: 20,
        defaultSnippetLength: 280,
        backupRetentionDays: 30
    )
}

private func makeNoteTagSourceNote(
    id: String,
    title: String,
    body: String,
    rawText: String? = nil,
    tags: [String]
) -> BearNote {
    let createdAt = Date(timeIntervalSince1970: 1_710_000_000)
    let modifiedAt = Date(timeIntervalSince1970: 1_710_000_500)

    return BearNote(
        ref: NoteRef(identifier: id),
        revision: NoteRevision(version: 3, createdAt: createdAt, modifiedAt: modifiedAt),
        title: title,
        body: body,
        rawText: rawText ?? BearText.composeRawText(title: title, body: body),
        tags: tags,
        archived: false,
        trashed: false,
        encrypted: false
    )
}

private final class NoteTagReadStore: @unchecked Sendable, BearReadStore {
    private let noteByID: [String: BearNote]

    init(noteByID: [String: BearNote]) {
        self.noteByID = noteByID
    }

    func findNotes(_ query: FindNotesQuery) throws -> DiscoveryNoteBatch { DiscoveryNoteBatch(notes: [], hasMore: false) }
    func note(id: String) throws -> BearNote? { noteByID[id] }
    func notes(withIDs ids: [String]) throws -> [BearNote] { [] }
    func listTags(_ query: ListTagsQuery) throws -> [TagSummary] { [] }
    func findNotes(title: String, modifiedAfter: Date?) throws -> [BearNote] { [] }
}

private actor NoteTagRecordingWriteTransport: BearWriteTransport {
    struct ReplaceCall: Sendable {
        let noteID: String
        let fullText: String
    }

    private(set) var replaceCalls: [ReplaceCall] = []

    func resolveSelectedNoteID(token _: String) async throws -> String {
        "selected-note"
    }

    func create(_ request: CreateNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: "created", title: request.title, status: "created", modifiedAt: nil)
    }

    func insertText(_ request: InsertTextRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func replaceAll(noteID: String, fullText: String, presentation: BearPresentationOptions) async throws -> MutationReceipt {
        replaceCalls.append(ReplaceCall(noteID: noteID, fullText: fullText))
        return MutationReceipt(noteID: noteID, title: "Inbox", status: "updated", modifiedAt: nil)
    }

    func addFile(_ request: AddFileRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "updated", modifiedAt: nil)
    }

    func open(_ request: OpenNoteRequest) async throws -> MutationReceipt {
        MutationReceipt(noteID: request.noteID, title: nil, status: "opened", modifiedAt: nil)
    }

    func openTag(_ request: OpenTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.tag, newTag: nil, status: "opened")
    }

    func renameTag(_ request: RenameTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.name, newTag: request.newName, status: "renamed")
    }

    func deleteTag(_ request: DeleteTagRequest) async throws -> TagMutationReceipt {
        TagMutationReceipt(tag: request.name, newTag: nil, status: "deleted")
    }

    func archive(noteID: String, showWindow: Bool) async throws -> MutationReceipt {
        MutationReceipt(noteID: noteID, title: nil, status: "archived", modifiedAt: nil)
    }
}
