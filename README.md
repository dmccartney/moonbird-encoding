# Moonbird Encoding
This contains my exploration of encoding [Moonbirds](https://moonbirds.xyz/) on-chain.

I first did some exploring of encoding the images and then turned to the metadata.

tl/dr: I got it down to `720 bytes/bird` using a tile-based RLE scheme w/ a color table.
But I'm kinda stuck there -- without access to the separate image layers, I can't play with a layer-toggling approach.

N.B.: this repo is a mess. I'm sharing for anyone who wants to cherry-pick methods.

## Images

I started out by downloading all the images (`curl ... [0-9999]`) and then analyzing them
manually to get a feel for the set (42 x 42 tiles of 24px and a few dozen colors per bird, etc).

### Naive: 5292 bytes / bird
The birds as PNGs were 6-7K each. But I figured we could improve on that by custom encoding.

Naively, each bird could be captured as a list of 42x42 3-byte RGB values, one for each tile.
That would result in `5292 bytes` per bird or ~50MB for all 10,000 birds.

### Global Colors: 2426 bytes / bird
My hunch was I could use a global color table to reduce the 3-bytes needed for each color.
Then each bird's tiles could reference smaller color codes.

So I wrote some scripts to extract the colors/tile data for each bird.

This gave me the global list of `1608 colors` across all 10,000 birds.

Pairing each color with a corresponding code between 0-1608 means color references only needed `11 bits` (max value 2048).

The global color table is ~4K but it reduced the per-bird size from `5292` to `2426 bytes`.

This was still pretty large. And looking at the long lists of repeated tiles I knew we could do better.

### RLE: 721 bytes / bird
I decided to use [RLE encoding](https://en.wikipedia.org/wiki/Run-length_encoding) to compress repeated tiles.

This takes a "run" (a sequence of repeated tiles) and collapses it into a single entry that includes the type and count.
e.g. `<Red><Red><Red><Red>` becomes `<4 Red>`

So the list of colors for the birds now becomes a list of `(count, color)` pairs. 
And I had to decide how many bits to spend on the `count`.

Looking at the birds, the longest repeated tile sequence would fit into `10 bits` (max value `1024`).
But on more detailed parts of the bird the `10 bits` would be a lot of unnecessary overhead.
Plus `10 bits` doesn't pack well with the `11 bits` needed for the color code.

So I decided to use `5 bits` (max value `32`) which limits the run size to 32 
(e.g. a run of 64 red tiles would take two entries).
But using `5 bits` instead of `10 bits` slims the size of shorter runs.
And it nicely packs with the color code into `16 bits` (`2 bytes`).

Applying this scheme reduced the per-bird size down to `721 bytes`.

At this point I decided to turn to the metadata to see if that would lead to something more powerful.

## Metadata: 34 bits / bird

I downloaded all the metadata (`curl ... [0-9999]`) and then wrote a script to 
gather the superset of all possible traits and values (including sometimes `(absent)` traits).

And then calculated how many bits of data each required.

In total there are `8 traits` with `124 values` which fit into `34 bits`:

| Trait | Count | Bits | Values |
| ---: | --- | --- | --- |
| Background | 11 | 4 | (absent), Blue, Cosmic Purple, Enlightened Purple, Glitch Red, Gray, Green, Jade Green, Pink, Purple, Yellow |
| Beak | 4 | 2 | (absent), Long, Short, Small |
| Body | 18 | 5 | (absent), Brave, Cosmic, Crescent, Emperor, Enlightened, Glitch, Golden, Guardian, Jade, Professor, Robot, Ruby Skeleton, Sage, Skeleton, Stark, Tabby, Tranquil |
| Eyes | 12 | 4 | (absent), Adorable, Angry, Diamond, Discerning, Fire, Heart, Moon, Open, Rainbow, Relaxed, Side-eye |
| Eyewear | 13 | 4 | (absent), 3D Glasses, Aviators, Big Tech, Black-rimmed Glasses, Eyepatch, Gazelles, Half-moon Spectacles, Jobs Glasses, Monocle, Rose-Colored Glasses, Sunglasses, Visor |
| Feathers | 19 | 5 | (absent), Black, Blue, Bone, Brown, Gray, Green, Legendary Bone, Legendary Brave, Legendary Crescent, Legendary Emperor, Legendary Guardian, Legendary Professor, Legendary Sage, Metal, Pink, Purple, Red, White |
| Headwear | 38 | 6 | (absent), Aviator's Cap, Backwards Hat, Bandana, Beanie, Bow, Bucket Hat, Captain's Cap, Chromie, Cowboy Hat, Crescent Talisman, Dancing Flame, Diamond, Durag, Fire, Flower, Forest Ranger, Grail, Gremplin, Halo, Headband, Headphones, Hero's Cap, Karate Band, Lincoln, Mohawk (Green), Mohawk (Pink), Moon Hat, Pirate's Hat, Queen's Crown, Raincloud, Rubber Duck, Skully, Space Helmet, Tiara, Tiny Crown, Witch's Hat, Wizard's Hat |
| Outerwear | 9 | 4 | (absent), Bomber Jacket, Diamond Necklace, Gold Chain, Hero's Tunic, Hoodie, Hoodie Down, Jean Jacket, Punk Jacket |

NOTE: for consistency, I sort the traits and values alphabetically.

For example, here's the encoded `34 bit` header for bird [#6158](https://opensea.io/assets/0x23581767a106ae21c074b2276d25e5c3e136a68b/6158):
```
┌──────────────────────────────────────────── Background: 6 --> Green
│    ┌───────────────────────────────────────────── Beak: 3 --> Small
│    │  ┌────────────────────────────────────────── Body: 3 --> Crescent
│    │  │     ┌──────────────────────────────────── Eyes: 9 --> Rainbow
│    │  │     │    ┌──────────────────────────── Eyewear: 0 --> (absent)
│    │  │     │    │    ┌────────────────────── Feathers: 1 --> Black
│    │  │     │    │    │     ┌──────────────── Headwear: 19 -> Halo
│    │  │     │    │    │     │      ┌──────── Outerwear: 0 --> (absent)
│    │  │     │    │    │     │      │    
│    │  │     │    │    │     │      │    
▼    ▼  ▼     ▼    ▼    ▼     ▼      ▼    
0110 11 00011 1001 0000 00001 010011 0000
```

# Conclusion

At this point it seems like the best strategy will be to use the metadata attributes and actually toggle layers.
I was hoping I could get the tile-oriented scheme slim enough. 
But I could only get it down to `~720 bytes / bird` which works out to `~7mb total` which is still very expensive.

I wish I had access to the separate image layers. But I don't, so I can't play with a layering approach.
(I spent a little time trying to scrape them together. But there are dependent layers that blend etc and 
I don't want to introduce any loss to the artwork by guessing). 

I'm bummed I hit a wall, but still excited to see how the official rendering contract puts it all together.
