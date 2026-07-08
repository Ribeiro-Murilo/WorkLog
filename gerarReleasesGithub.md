```
make publish VERSION=0.1.1

git tag v0.1.1
git push origin main --tags
gh release create v0.1.1 build/WorkLog-0.1.1.zip --title "v0.1.1" --notes-file GITHUB_RELEASE_NOTES.md
```