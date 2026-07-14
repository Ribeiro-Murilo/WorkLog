```
make publish VERSION=0.1.2

git tag v0.1.2
git push origin main --tags
gh release create v0.1.2 build/WorkLog-0.1.2.zip --title "v0.1.2" --notes-file GITHUB_RELEASE_NOTES.md
```