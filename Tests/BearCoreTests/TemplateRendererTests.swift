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
func bearTextParsesTitleAndBody() {
    let parsed = BearText.parse(rawText: "# Example\n\nBody line", fallbackTitle: "Fallback")

    #expect(parsed.titleLine == "Example")
    #expect(parsed.body == "Body line")
}

@Test
func bearTextComposesRawText() {
    let raw = BearText.composeRawText(title: "Example", body: "Body line")
    #expect(raw == "# Example\n\nBody line")
}
