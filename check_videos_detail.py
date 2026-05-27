import requests
r = requests.get("https://manikadahal-sabina-chess.hf.space/api/media/videos/")
data = r.json()
print("Number of videos:", len(data))
for v in data:
    print(f"ID: {v['id']}")
    print(f"Title: {v['title']}")
    print(f"Video URL: {v['video_url']}")
    print(f"Stream URL: {v['stream_url']}")
    print(f"Thumbnail URL: {v['thumbnail_url']}")
    print("-" * 40)
