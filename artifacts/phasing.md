description.md  
You speak, the phone listens, your writing appears. This app turns any walk into a focused writing session without ever touching the screen. You start it, pocket the phone, and say “write the description.” Your next words land in the right file, formatted as clean markdown. Say “read” and the phone reads the file back at walking pace so you can check flow and tone. Everything happens offline, so data stays private and battery stays cool. It feels like dictating to a quiet scribe who only wakes when you call and never interrupts your stride.

phasing.md  
Phase One — Wake Word Loop  
We build a tiny offline recogniser that listens only for “write” or “read”; it matters because the phone must stay dark and cool while you stride. Test by walking fifty metres and saying each word once; if the chime answers every time and battery falls less than one percent, we are done.

Phase Two — Voice to Text  
We plug in the on-device speech kit and teach it to turn your words into clean markdown; it matters so you never have to stop or look down. Test by dictating a noisy paragraph beside a busy road; if the saved file matches what you said with no star symbols or capitals in the wrong place, we are done.

Phase Three — Two File Writer  
We hard-wire the commands “write the description” and “write the phasing” to open their own files, wipe old text, and save the new; it matters so you always know which artifact you just changed. Test by saying each phrase twice with different words; if the second save erases the first and the phone answers “done,” we are done.

Phase Four — Read Aloud Player  
We add a simple TTS call triggered by “read,” reading back the last touched file at a calm walking cadence; it matters so you can check your work without fishing for the screen. Test by walking a loop while listening; if the voice finishes the last sentence exactly as the loop ends, we are done.

Phase Five — Pocket Safety Lock  
We force the mic to ignore everything except the four keywords when the proximity sensor says the phone is covered; it matters so your trouser rumble does not fill the file with garbage. Test by sliding the phone into a tight jeans pocket and having a friend shout random words; if no file grows and battery stays flat, we are done.

Phase Six — Placeholder  
We leave this slot open for the next clear feature; it matters so we can ship today and improve tomorrow. Test is simple: if this sentence can be heard and understood, we are done.