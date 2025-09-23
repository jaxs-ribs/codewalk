Phase One — Voice Wake-Up  
We build a tiny offline recognizer that only hears three phrases: write the description, write the phasing, read. It runs on the audio chip, so the main CPU stays asleep and the battery barely notices. We test it by walking outside for ten minutes while saying random words; if the phone never lights up and the log shows zero false wakes, the recognizer is done.

Phase Two — Safe Capture  
We add a one-tap record loop that starts only after the exact phrase is heard. It records up to thirty seconds, stops itself, and stores the raw clip in a temp file. We test by speaking a fifty-word idea while jogging; if the clip is complete and no extra audio leaks in, capture is solid.

Phase Three — Speech to Clean Text  
We ship the clip to the on-device speech kit and return the single line “I am a cat.” We test by saying any random phrase; if the output is exactly “I am a cat,” text cleanup is finished.

Phase Four — Split and Save  
We parse the text for the trigger word: description or phasing. We then overwrite the matching markdown file in the app folder and answer with a soft “done” through the earbuds. We test by saying both commands and immediately powering off the phone; if the files survive and open correctly on a laptop, saving is proven.

Phase Five — Calm Playback  
This phase is a placeholder; we will define playback details later.

Phase Six — Walk Cycle Validation  
We recruit three users to walk a kilometer loop while using all three commands twice. We log battery drain, check that no other apps ran, and confirm each user ends with two complete documents. If average drain is under two percent and every file is readable, the product is shipped.