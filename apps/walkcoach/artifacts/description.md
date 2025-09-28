# Project Description

We're building a real-time tariff tracker that keeps importers and exporters instantly informed about changing duty rates between the US and Vietnam. The app monitors live customs data and pushes notifications the moment rates shift, so businesses never get caught off guard by sudden 20 percent jumps like we saw in July 2025.

Here's how it works. Every night our Python FastAPI service scrapes official customs databases and trade announcements, then updates our PostgreSQL database with the latest rates. When users open the app, they see current tariffs for every product category, plus historical charts showing how rates moved from 2.5 percent to today's 17.4 percent average. The moment something changes, we push alerts through WebSocket connections so users get pinged immediately on their phones.

We're making this available two ways. There's a React Native mobile app built with Expo for people on the go, and a web dashboard using React for desktop users who need bigger charts. Both pull from the same backend, so data stays consistent whether you're checking on your phone between meetings or analyzing trends at your desk.

The whole thing runs on AWS for reliability. We containerize everything with Fargate, cache globally through CloudFront, and use EventBridge to schedule our nightly data pulls. This means whether Vietnam's exports hit 137 billion again or the US changes rates tomorrow, our system scales automatically and keeps everyone informed in real time.