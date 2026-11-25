type AppProps = {
  title: string;
  items: string[];
};

export function App({ title, items }: AppProps) {
  return (
    <main>
      <h1>{title}</h1>
      <ul>
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </main>
  );
}
