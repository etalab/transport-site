# Changelog for NeTEx validator

## 0.1.0 - aka saas-production

Base version. Uses the enroute:starter-kit profile. Issues are grouped per code
without any specific inline documentation.

## 0.2.0

- XSD validation is reenabled.
- Issues are now grouped by "category"
  - category `"xsd-schema"` for errors related to the XSD validation (errors
      prefixed `xsd-`).
  - category `"base-rules"` for checks of the `enroute:starter-kit` profile.

Categories are used to build the summary of a NeTEx validation. Each category
has a title, a description (providing links to any relevant documentation), and
some hints for usual errors (optional).

## 0.2.1

- Uses the profile `pan:french_profile:1` (which includes rules from
    `enroute:starter-kit`)
  - new rules introduced to check specific rules of the French profile
      (mandatory attributes)
