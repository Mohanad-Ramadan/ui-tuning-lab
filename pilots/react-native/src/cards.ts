export type CardConfig = {
  radius: number; // px
  gap: number;    // px between cards
  padding: number; // px inside each card
};

export const cardDefaults: CardConfig = { radius: 12, gap: 8, padding: 16 };

export const cards = [
  { title: "Inbox", body: "3 unread messages" },
  { title: "Calendar", body: "Standup at 10:00" },
  { title: "Tasks", body: "2 due today" },
];
