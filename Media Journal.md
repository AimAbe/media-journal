# Media Journal

A running dashboard over everything logged by the Media Journal plugin —
films, books, games, comics, music. Powered by [Dataview](https://blacksmithgu.github.io/obsidian-dataview/);
every table below reads live off the frontmatter in `Media/**`.

## This month

```dataview
TABLE type, creator, rating, date_logged AS "Logged"
FROM "Media"
WHERE dateformat(date_logged, "yyyy-MM") = dateformat(date(today), "yyyy-MM")
SORT date_logged DESC
```

## Best of the year

```dataview
TABLE title, type, creator, year AS "Released", rating
FROM "Media"
WHERE date_logged.year = date(today).year AND rating >= 4.5
SORT rating DESC
```

## In progress

```dataview
TABLE type, creator, status, date_logged AS "Started"
FROM "Media"
WHERE status = "playing" OR status = "reading" OR status = "rewatching"
SORT date_logged DESC
```

## By type

### 🎮 Games

```dataview
TABLE creator AS "Developer", platform, hours_played AS "Hours", rating, status, date_logged AS "Logged"
FROM "Media/Games"
SORT date_logged DESC
```

### 🎬 Films

```dataview
TABLE creator AS "Director", year, runtime, rewatch, rating, date_logged AS "Logged"
FROM "Media/Films"
SORT date_logged DESC
```

### 📚 Books

```dataview
TABLE creator AS "Author", pages, format, rating, status, date_logged AS "Logged"
FROM "Media/Books"
SORT date_logged DESC
```

### 🎵 Music

```dataview
TABLE creator AS "Artist", format, label, rating, date_logged AS "Logged"
FROM "Media/Music"
SORT date_logged DESC
```

### 💬 Comics

```dataview
TABLE writer, artist, publisher, issues, rating, status, date_logged AS "Logged"
FROM "Media/Comics"
SORT date_logged DESC
```

## All-time stats

```dataview
TABLE length(rows) AS "Count", round(average(filter(rows.rating, (r) => r > 0)), 2) AS "Avg rating"
FROM "Media"
WHERE type
GROUP BY type
SORT length(rows) DESC
```
