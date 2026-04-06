import BearCore
import Testing

@Test
func templateValidatorAcceptsOneContentAndOneTagsSlot() {
    let report = BearTemplateValidator.validate("{{content}}\n\n{{tags}}\n")

    #expect(!report.hasErrors)
    #expect(report.warnings.isEmpty)
}

@Test
func templateValidatorCombinesMissingRequiredSlots() {
    let report = BearTemplateValidator.validate("{{title}}\n\nBody only\n")

    #expect(report.errors.count == 1)
    #expect(report.errors.first?.message == "Template must include one `{{content}}` slot and one `{{tags}}` slot.")
}

@Test
func templateValidatorStillFlagsMissingContentSeparately() {
    let report = BearTemplateValidator.validate("{{tags}}\n")

    #expect(report.errors.count == 1)
    #expect(report.errors.first?.message == "Template must include one `{{content}}` slot.")
}

@Test
func templateValidatorStillFlagsMissingTagsSeparately() {
    let report = BearTemplateValidator.validate("{{content}}\n")

    #expect(report.errors.count == 1)
    #expect(report.errors.first?.message == "Template must include one `{{tags}}` slot.")
}

@Test
func templateValidatorWarnsAboutUnknownPlaceholders() {
    let report = BearTemplateValidator.validate("{{content}}\n\n{{tags}}\n\n{{summary}}\n{{summary}}\n")

    #expect(!report.hasErrors)
    #expect(report.warnings.count == 1)
    #expect(report.warnings.first?.message == "Unknown placeholder `{{summary}}` will be saved literally.")
}

@Test
func templateValidatorWarnsWhenTitlePlaceholderIsUsed() {
    let report = BearTemplateValidator.validate("{{title}}\n\n{{content}}\n\n{{tags}}\n")

    #expect(!report.hasErrors)
    #expect(report.warnings.count == 1)
    #expect(report.warnings.first?.message == "Ursus applies the template below Bear's note title. Avoid `{{title}}` unless you intentionally want title text inside the body.")
}
