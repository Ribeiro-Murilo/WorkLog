```
make publish VERSION=x.x.x

git tag vx.x.x
git push origin main --tags
gh release create vx.x.x build/WorkLog-x.x.x.zip --title "vx.x.x" --notes-file GITHUB_RELEASE_NOTES.md
```