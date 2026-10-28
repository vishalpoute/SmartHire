"""Versioned extraction suggestions; only the owner can confirm these as skills."""

import re
import unicodedata

TAXONOMY_VERSION = "skills-v1"
ALIASES = {
    "Flutter": ("flutter",),
    "Dart": ("dart",),
    "Firebase": ("firebase",),
    "Python": ("python",),
    "FastAPI": ("fastapi", "fast api"),
    "Django": ("django",),
    "JavaScript": ("javascript", "java script"),
    "TypeScript": ("typescript",),
    "React": ("react", "reactjs", "react.js"),
    "Node.js": ("node.js", "nodejs"),
    "Java": ("java",),
    "Kotlin": ("kotlin",),
    "Swift": ("swift",),
    "C++": ("c++",),
    "C#": ("c#", "c sharp"),
    "SQL": ("sql",),
    "PostgreSQL": ("postgresql", "postgres"),
    "MySQL": ("mysql",),
    "MongoDB": ("mongodb",),
    "Redis": ("redis",),
    "Docker": ("docker",),
    "Kubernetes": ("kubernetes", "k8s"),
    "Git": ("git",),
    "Linux": ("linux",),
    "AWS": ("aws", "amazon web services"),
    "Azure": ("azure",),
    "Google Cloud": ("google cloud", "gcp"),
    "HTML": ("html", "html5"),
    "CSS": ("css", "css3"),
    "GraphQL": ("graphql",),
}
PATTERNS = {
    name: re.compile(r"(?<!\w)(?:" + "|".join(re.escape(alias) for alias in aliases) + r")(?!\w)")
    for name, aliases in ALIASES.items()
}


def suggest_skills(text):
    normalized = unicodedata.normalize("NFKC", text).casefold()
    return [name for name, pattern in PATTERNS.items() if pattern.search(normalized)][:30]
