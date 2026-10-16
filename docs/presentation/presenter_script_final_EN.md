# syncy Presenter Script (English, final)

**Slide 1 · Cover**
Hi everyone, we're Team M12. Today we'd like to introduce syncy, where feedback turns into your next practice.

**Slide 2 · Team M12**
A quick look at our team. On design, Baekdo is our product designer, Yeon is our product and brand designer, and I'm Seoyeong, our UX researcher and designer. On development, Anna is UX Design and developer, Martin and Moo are our iOS developers. This project started from Martin's experience playing in bands.

**Slide 3 · Story & Context (1/3)**
Anyone who has played in a band knows this: the more you rehearse, the better the show. But if music isn't your job, it's hard to find a time that works for everyone, and finding a place to rehearse costs money and space. So the rehearsal time we get before a show is always limited.
That's why solo practice between rehearsals matters. And it's not just about your own part. It's about creating the moments where you lock in with everyone else. Before one of our shows, Martin recorded just the drums at rehearsal and practiced along to that track. It made a real difference.

**Slide 4 · Story & Context (2/3)**
For that practice to work, you need to know exactly what to fix. After rehearsal, you hear feedback like: "The kick drum rushes a little going into the chorus, so it's off from the bass." "In the second verse's bridge, the guitar covers the vocal." "The tempo speeds up in the fill right before the last chorus." To people in a band, that's precise feedback. But most of it is only said out loud, and then it's gone.

**Slide 5 · Story & Context (3/3)**
Even when it's written down, it ends up scattered across messenger apps, full-band recordings, part recordings, and section clips. After a while, it's hard to remember who said it, or which part of which song it was about. With communication breaking down like this, the little rehearsal time we have goes to trading feedback instead of locking in together. Rehearsal becomes inefficient, and in the end it's hard to prepare a good show.

**Slide 6 · Target Use Case**
Our users are hobby bands preparing for a show. Their pain point is that feedback from rehearsal gets scattered and is only spoken, so communication breaks down and it never reaches solo practice. As a result, rehearsal time is used inefficiently. And no existing app offers this kind of feedback.

**Slide 7 · Challenge Response**
Our app helps band members who received feedback at rehearsal improve their playing by the next rehearsal. It does this by connecting rehearsal feedback to section-by-section practice on their own sheet, and by letting them check their improvement through recordings and their bandmates' comments.

**Slide 8 · What changes**
It comes down to three things. One, section practice: rehearsal feedback stays on the matching section of your sheet, so you can practice it right away. Two, check improvement: you re-record, compare with the original, and see through your bandmates' comments whether it got better. Three, time to sync up: you can spend rehearsal time locking in what you've practiced. Even if a band can't rehearse more often, we hope it can make better use of the rehearsals it has, and prepare a better show.

**Slide 9 · Flow 1: Home**
Let's walk through the flow. On the home screen, you see the feedback you've received for each song, and its status: needs practice, waiting for a comment, or practice again. "Start practice" takes you straight to that section. On the right are comment requests from bandmates who've re-recorded a part.

**Slide 10 · Flow 2: Show**
The show page keeps the date, venue, members, and weekly rehearsal time in one place. You build the setlist here and pick the song to practice.

**Slide 11 · Flow 3: Practice with the recording**
On the practice screen, the rehearsal recording is split by instrument, with feedback pinned exactly where it happened. You can mute or adjust each part, loop a section, and record yourself playing along with the band.

**Slide 12 · Flow 4: Sheet**
Each member uploads the sheet for their own part. Switch to sheet view, and the same feedback shows up right on your sheet. You can write notes on it and loop the passage until it sits right.

**Slide 13 · Flow 5: Shared note**
To leave feedback, you select a range of bars on the sheet, choose who gets the note, the whole band or just one part, and pick a type. Feedback is something to fix, like "Pitch drops slightly in bars 5 to 10." A performance note is about how we play it together, like "Bring it down here, then build into the last chorus."

**Slide 14 · Flow 6: Before / After**
Finally, the person who got the note practices that section and records a new take. They can compare before and after, ask for a comment, and confirm it's done. That's the loop we care about most: feedback that leads to the next practice.

**Slide 15 · Proof of Concept: the question**
By the time we reached lo-fi, we had our minimum feature set. But one question kept coming up, both inside and outside our team: will this really help band practice, and will real bands actually use it? So we decided to run a proof of concept.

**Slide 16 · Proof of Concept: the prototype**
We built a prototype with only the core features. First, it splits a rehearsal recording by part. Then you listen to a specific part or section and leave feedback right where you want it. Finally, each person uploads a new take that reflects the feedback. That way, members give and get feedback through the recordings themselves.

**Slide 17 · Proof of Concept: field test**
We reached out to bands and music academies in Pohang and tested the prototype with them. It gave us confidence that it addresses the pain point we started with. One teacher said, "Other programs can split instruments. But leaving a comment and re-recording? None of them do that." Teachers also saw it as a tool for music lessons, something we hadn't considered.

**Slide 18 · PoC to Ideation: Interface Ideas**
We turned what we learned from the PoC into interface ideas. First, identify the need: the feedback we reviewed showed that people need feedback that is easy to share, easy to understand, and easy to apply in practice. Second, decide on a structured approach: we chose type-specific inputs linked to the selected segment, to keep feedback simple, precise, and actionable. Third, translate those decisions into the interface: users select a segment and a recipient, choose a feedback type, and fill in details through controls built for that type. The types are timing, volume and balance, harmony, expression, and others.

**Slide 19 · Learning Questions**
At this point, we have two questions.
First, a follow-up to feedback from our last Learning Community: how can we help members actually start practicing on the feedback they receive? Specifically, how do we keep it from feeling like homework, how should we show different types of feedback, and what helps people practice on it effectively?
Second, our roadmap. From a product perspective, what should we be considering at this stage, and what should we think about as we develop it further? And with about six weeks left, what scope should we aim for, for both the challenge and the product?

**Slide 20 · Thank you**
That's syncy. Thank you for your time, and we're happy to take your questions.
