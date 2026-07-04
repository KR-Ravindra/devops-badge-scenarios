# Step 1 — Run the registry and publish an image

Goal:

- A registry answers at `http://localhost:5000/v2/`.
- The image `localhost:5000/internal/app:1.0` exists **in the registry** (visible in
  `http://localhost:5000/v2/_catalog`).

Then click **Check**.

<details>
<summary>Hint</summary>

```
docker run -d -p 5000:5000 --name registry registry:2
docker tag alpine:3.20 localhost:5000/internal/app:1.0
docker push localhost:5000/internal/app:1.0
curl http://localhost:5000/v2/_catalog
```
</details>
