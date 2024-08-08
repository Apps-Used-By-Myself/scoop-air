# Air

## Attention

This is a very personalized bucket, and many of the manifests installed in it are beta versions of the application with some preprocessing.

Please check the manifests for changes and make sure they match your needs before installing.

If you only need a few apps from this repository, use `scoop install https://raw.githubusercontent.com/wordpure/scoop-air/main/bucket/<manifestname>.json` to install them instead of adding the bucket.

Because `air` is very high in the alphabetical order of unofficial buckets, installing apps without specifying a bucket may inadvertently install apps from this bucket.

## Usage

To add this bucket to scoop, run the following command in PowerShell:

```pwsh
scoop bucket add air https://github.com/wordpure/scoop-air
```

then

```pwsh
scoop install air/<manifestname>
```
