import { cards } from "./cards";
import type { CardConfig } from "./cards";

export function CardList({ config }: { config: CardConfig }) {
  return (
    <section className="cards" style={{ gap: config.gap }}>
      {cards.map(card => (
        <article key={card.title} className="card"
          style={{ borderRadius: config.radius, padding: config.padding }}>
          <h2>{card.title}</h2>
          <p>{card.body}</p>
        </article>
      ))}
    </section>
  );
}
