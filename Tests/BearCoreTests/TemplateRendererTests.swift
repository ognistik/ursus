import BearCore
import Testing

@Test
func templateRendererRendersSingleTemplateDocument() {
    let context = TemplateContext(
        title: "Test",
        content: "Hello world",
        tags: ["inbox", "#swift"]
    )

    let rendered = TemplateRenderer.renderDocument(
        context: context,
        template: "---\n{{tags}}\n---\n{{content}}"
    )

    #expect(rendered == "---\n#inbox #swift\n---\nHello world")
}

@Test
func templateRendererWrapsTagsThatContainSpaces() {
    let context = TemplateContext(
        title: "Test",
        content: "Hello world",
        tags: ["deep work", "#focus mode#"]
    )

    let rendered = TemplateRenderer.renderDocument(
        context: context,
        template: "{{tags}}"
    )

    #expect(rendered == "#deep work# #focus mode#")
}

@Test
func templateRendererCanPreserveOneEmptyContentLineWhileTrimmingOuterTemplateWhitespace() {
    let context = TemplateContext(
        title: "Test",
        content: "",
        tags: []
    )

    let rendered = TemplateRenderer.renderDocument(
        context: context,
        template: "{{content}}\n\n{{tags}}\n",
        preserveEmptyContentLine: true
    )

    #expect(rendered == "\n")
}

@Test
func bearTextParsesTitleAndBody() {
    let parsed = BearText.parse(rawText: "# Example\n\nBody line", fallbackTitle: "Fallback")

    #expect(parsed.titleLine == "Example")
    #expect(parsed.frontMatter == nil)
    #expect(parsed.hasExplicitTitle == true)
    #expect(parsed.body == "Body line")
}

@Test
func bearTextComposesRawText() {
    let raw = BearText.composeRawText(title: "Example", body: "Body line")
    #expect(raw == "# Example\n\nBody line")
}

@Test
func bearTextParsesFrontMatterBeforeTitleAndBody() {
    let parsed = BearText.parse(
        rawText: """
        ---
        key1: This is a test
        # Actually, I am just including some random text here.
        ---
        # Test Note
        this is the body
        """,
        fallbackTitle: "Fallback"
    )

    #expect(parsed.frontMatter?.content == "key1: This is a test\n# Actually, I am just including some random text here.")
    #expect(parsed.titleLine == "Test Note")
    #expect(parsed.hasExplicitTitle == true)
    #expect(parsed.body == "this is the body")
}

@Test
func bearTextParsesFrontMatterWithoutExplicitTitle() {
    let parsed = BearText.parse(
        rawText: """
        ---
        key1: value
        key2: another
        ---
        this is the body
        """,
        fallbackTitle: ""
    )

    #expect(parsed.frontMatter?.content == "key1: value\nkey2: another")
    #expect(parsed.titleLine == nil)
    #expect(parsed.hasExplicitTitle == false)
    #expect(parsed.body == "this is the body")
}

@Test
func bearTextComposesTitlelessFrontMatterNotes() {
    let raw = BearText.composeRawText(
        title: "",
        hasExplicitTitle: false,
        body: "Body line",
        frontMatter: BearFrontMatter(content: "key: value"),
        separator: "\n\n"
    )

    #expect(raw == "---\nkey: value\n---\nBody line")
}

@Test
func bearTagExtractsWrappedBareAndSpacedLiteralTags() {
    let tokens = BearTag.extractTokens(
        from: "#codexsinglewrapped# and #codex single wrapped# and #codexsingleplain and #parent/subtag"
    )

    #expect(tokens.map(\.normalizedName) == [
        "codexsinglewrapped",
        "codex single wrapped",
        "codexsingleplain",
        "parent/subtag",
    ])
}
