# SmartHire design specification

Use the existing forest-green/neutral Material 3 theme in `apps/flutter_app/lib/core/theme/app_theme.dart` as the source for implementation tokens.

| Token | Value | Use |
| --- | --- | --- |
| Ink/primary | `#173C33` | Headings, primary actions and identity |
| Muted | `#67746E` | Supporting text |
| Canvas | `#F7F8F4` | Page background |
| Line | `#E4E8E1` | Borders/dividers |
| Surface | `#FFFFFF` | Cards and form fields |

## Typography

Retain Flutter's platform/default Material font family; no custom family is currently configured. Headline large: 36px/700, letter spacing -1.2; headline small: 24px/700, spacing -0.6; title: 19px/600; body: 14px with 1.5 line height. Respect text scaling and adapt headings on narrow screens.

## Components and layout

Inputs use white fill, 12px corner radius and 18px content padding. Primary buttons use 10px radius with clear action verbs. Keep one dominant action per task, consistent spacing and restrained borders. Reuse theme/components instead of introducing separate visual systems per feature.

Use responsive cards and readable content widths; avoid dense tables on phones. Status chips need textual labels and semantic Material error/success treatment; verify contrast rather than assuming every token pairing is accessible. Provide visible focus, keyboard order, appropriate touch targets and screen-reader names. Avoid decorative assets that add download cost without supporting a task.

## Review gate

Check loading/empty/error/success states at narrow and desktop sizes, text scaling and keyboard navigation. Keep operational details, internal keys and implementation flags out of product flows.
